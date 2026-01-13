package merge

import (
	"encoding/json"
	"fmt"
	"os"
	"regexp"
	"strings"
	"time"

	"github.com/supabase/postgres/nix/packages/sbom/internal/spdx"
)

type Merger struct{}

func NewMerger() *Merger {
	return &Merger{}
}

func (m *Merger) Merge(ubuntuPath, nixPath string) (*spdx.Document, error) {
	// Load Ubuntu SBOM
	ubuntuDoc, err := m.loadDocument(ubuntuPath)
	if err != nil {
		return nil, fmt.Errorf("failed to load Ubuntu SBOM: %w", err)
	}

	// Load Nix SBOM
	nixDoc, err := m.loadDocument(nixPath)
	if err != nil {
		return nil, fmt.Errorf("failed to load Nix SBOM: %w", err)
	}

	uuid, err := spdx.GenerateUUID()
	if err != nil {
		return nil, fmt.Errorf("failed to generate UUID: %w", err)
	}

	// Create merged document
	mergedDoc := &spdx.Document{
		SPDXVersion:       "SPDX-2.3",
		DataLicense:       "CC0-1.0",
		SPDXID:            "SPDXRef-DOCUMENT",
		Name:              fmt.Sprintf("Ubuntu-Nix-System-SBOM-%s", time.Now().Format("2006-01-02")),
		DocumentNamespace: fmt.Sprintf("https://sbom.ubuntu-nix.system/%s", uuid),
		CreationInfo: spdx.CreationInfo{
			Created:            time.Now().UTC().Format(time.RFC3339),
			Creators:           m.mergeCreators(ubuntuDoc, nixDoc),
			LicenseListVersion: "3.20",
		},
		Packages:      []spdx.Package{},
		Relationships: []spdx.Relationship{},
	}

	// Create the single root System package
	systemPkg := spdx.Package{
		SPDXID:           "SPDXRef-System",
		Name:             "Ubuntu-Nix-System",
		DownloadLocation: "NOASSERTION",
		FilesAnalyzed:    false,
		LicenseConcluded: "NOASSERTION",
		LicenseDeclared:  "NOASSERTION",
		CopyrightText:    "NOASSERTION",
		Description:      "Combined Ubuntu and Nix package system",
	}
	mergedDoc.Packages = append(mergedDoc.Packages, systemPkg)

	// Add document describes relationship
	mergedDoc.Relationships = append(mergedDoc.Relationships, spdx.Relationship{
		SPDXElementID:      "SPDXRef-DOCUMENT",
		RelatedSPDXElement: "SPDXRef-System",
		RelationshipType:   "DESCRIBES",
	})

	// Process Ubuntu packages (skip the root package)
	ubuntuCount := 0
	for _, pkg := range ubuntuDoc.Packages {
		if pkg.SPDXID == "SPDXRef-Ubuntu-System" || pkg.SPDXID == "SPDXRef-System" {
			continue // Skip root packages
		}

		// Ensure SPDXID has Ubuntu prefix
		if !strings.HasPrefix(pkg.SPDXID, "SPDXRef-Ubuntu-") {
			pkg.SPDXID = m.renumberSPDXID(pkg.SPDXID, "Ubuntu")
		}

		mergedDoc.Packages = append(mergedDoc.Packages, pkg)

		// Add relationship to system root
		mergedDoc.Relationships = append(mergedDoc.Relationships, spdx.Relationship{
			SPDXElementID:      "SPDXRef-System",
			RelatedSPDXElement: pkg.SPDXID,
			RelationshipType:   "CONTAINS",
		})
		ubuntuCount++
	}

	// Process Nix packages (skip any root packages)
	nixCount := 0
	for _, pkg := range nixDoc.Packages {
		// Skip root/system packages
		if strings.Contains(strings.ToLower(pkg.Name), "system") &&
			(pkg.SPDXID == "SPDXRef-DOCUMENT" || strings.HasSuffix(pkg.SPDXID, "-System")) {
			continue
		}

		// Ensure SPDXID has Nix prefix to avoid conflicts
		if !strings.HasPrefix(pkg.SPDXID, "SPDXRef-Nix-") {
			pkg.SPDXID = m.renumberSPDXID(pkg.SPDXID, "Nix")
		}

		// Clean up invalid CPE references from sbomnix
		pkg.ExternalRefs = m.cleanExternalRefs(pkg.ExternalRefs)

		mergedDoc.Packages = append(mergedDoc.Packages, pkg)

		// Add relationship to system root
		mergedDoc.Relationships = append(mergedDoc.Relationships, spdx.Relationship{
			SPDXElementID:      "SPDXRef-System",
			RelatedSPDXElement: pkg.SPDXID,
			RelationshipType:   "CONTAINS",
		})
		nixCount++
	}

	fmt.Printf("Merged %d Ubuntu packages and %d Nix packages\n", ubuntuCount, nixCount)

	return mergedDoc, nil
}

func (m *Merger) loadDocument(path string) (*spdx.Document, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}

	var doc spdx.Document
	if err := json.Unmarshal(data, &doc); err != nil {
		return nil, err
	}

	return &doc, nil
}

func (m *Merger) mergeCreators(ubuntuDoc, nixDoc *spdx.Document) []string {
	creatorMap := make(map[string]bool)
	var creators []string

	// Add creators from both documents
	for _, creator := range ubuntuDoc.CreationInfo.Creators {
		if !creatorMap[creator] {
			creators = append(creators, creator)
			creatorMap[creator] = true
		}
	}

	for _, creator := range nixDoc.CreationInfo.Creators {
		if !creatorMap[creator] {
			creators = append(creators, creator)
			creatorMap[creator] = true
		}
	}

	// Add merger tool
	mergerTool := "Tool: ubuntu-nix-sbom-merger-1.0"
	if !creatorMap[mergerTool] {
		creators = append(creators, mergerTool)
	}

	return creators
}

func (m *Merger) renumberSPDXID(originalID, prefix string) string {
	// Extract the base name from the SPDXID
	re := regexp.MustCompile(`SPDXRef-(.+)`)
	matches := re.FindStringSubmatch(originalID)

	if len(matches) > 1 {
		baseName := matches[1]
		return fmt.Sprintf("SPDXRef-%s-%s", prefix, baseName)
	}

	// Fallback: just add prefix
	return fmt.Sprintf("SPDXRef-%s-%s", prefix, strings.TrimPrefix(originalID, "SPDXRef-"))
}

func (m *Merger) Save(doc *spdx.Document, outputPath string) error {
	file, err := os.Create(outputPath)
	if err != nil {
		return err
	}
	defer file.Close()

	encoder := json.NewEncoder(file)
	encoder.SetIndent("", "  ")

	return encoder.Encode(doc)
}

func (m *Merger) cleanExternalRefs(refs []spdx.ExternalRef) []spdx.ExternalRef {
	// CPE 2.3 regex pattern - validates proper CPE format
	// Format: cpe:2.3:part:vendor:product:version:update:edition:language:sw_edition:target_sw:target_hw:other
	cpePattern := regexp.MustCompile(`^cpe:2\.3:[aho\*\-](:(((\?*|\*?)([a-zA-Z0-9\-\._]|(\\[\\\*\?!"#$%&'\(\)\+,\/:;<=>@\[\]\^` + "`" + `\{\|}~]))+(\?*|\*?))|[\*\-])){5}(:(([a-zA-Z]{2,3}(-([a-zA-Z]{2}|[0-9]{3}))?)|[\*\-]))(:(((\?*|\*?)([a-zA-Z0-9\-\._]|(\\[\\\*\?!"#$%&'\(\)\+,\/:;<=>@\[\]\^` + "`" + `\{\|}~]))+(\?*|\*?))|[\*\-])){4}$`)

	cleaned := []spdx.ExternalRef{}
	for _, ref := range refs {
		// If it's a CPE reference, validate and fix it if needed
		if ref.Type == "cpe23Type" {
			if cpePattern.MatchString(ref.Locator) {
				// Valid CPE, keep it as-is
				cleaned = append(cleaned, ref)
			} else {
				// Invalid CPE, try to fix it
				fixedCPE := m.fixCPEFormat(ref.Locator)
				ref.Locator = fixedCPE
				cleaned = append(cleaned, ref)
			}
		} else {
			// Not a CPE reference, keep it
			cleaned = append(cleaned, ref)
		}
	}
	return cleaned
}

func (m *Merger) fixCPEFormat(cpe string) string {
	// Parse malformed CPE from sbomnix and fix it
	// Common issue: cpe:2.3:a:product:product::*:*:*:*:*:*:*
	// Should be:    cpe:2.3:a:vendor:product:version:*:*:*:*:*:*:*
	// CPE 2.3 has 13 components total (including the cpe:2.3 prefix)

	if !strings.HasPrefix(cpe, "cpe:2.3:") {
		return cpe // Not a CPE, return as-is
	}

	parts := strings.Split(cpe, ":")
	if len(parts) < 4 {
		return cpe // Too short, can't fix
	}

	// Extract the part (a=application, h=hardware, o=os)
	part := parts[2]

	// Extract what looks like product name (usually parts[3] or parts[4])
	productName := parts[3]

	// Check if vendor field is missing or same as product (common sbomnix issue)
	// Example: cpe:2.3:a:pg_cron:pg_cron::*:*:*:*:*:*:*
	// The pattern is: part:product:product:empty_version:...
	// We want: part:vendor:product:version:...

	vendor := "*" // Default to wildcard if we can't determine vendor
	product := productName
	version := "*"

	// If there are 4+ parts after cpe:2.3, check the structure
	if len(parts) >= 5 {
		// Check if parts[3] and parts[4] are the same (common in sbomnix output)
		if parts[3] == parts[4] {
			// Likely format: cpe:2.3:a:product:product::...
			// Use the product name for both vendor and product
			vendor = parts[3]
			product = parts[3]
			// Check if there's a version in parts[5]
			if len(parts) >= 6 && parts[5] != "" && parts[5] != "*" {
				version = parts[5]
			}
		} else {
			// Different vendor and product, keep them
			vendor = parts[3]
			product = parts[4]
			if len(parts) >= 6 && parts[5] != "" && parts[5] != "*" {
				version = parts[5]
			}
		}
	}

	// Sanitize vendor/product names - remove invalid characters
	vendor = sanitizeCPEComponent(vendor)
	product = sanitizeCPEComponent(product)
	version = sanitizeCPEComponent(version)

	// Build a valid CPE 2.3 string with 13 components
	// Format: cpe:2.3:part:vendor:product:version:update:edition:language:sw_edition:target_sw:target_hw:other
	fixedCPE := fmt.Sprintf("cpe:2.3:%s:%s:%s:%s:*:*:*:*:*:*:*",
		part, vendor, product, version)

	return fixedCPE
}

func sanitizeCPEComponent(component string) string {
	// Remove or replace characters that aren't allowed in CPE components
	// Allowed: alphanumeric, dash, underscore, period
	// Replace underscores with dashes (more standard)
	component = strings.ReplaceAll(component, "_", "-")

	// If empty or just wildcards, return wildcard
	if component == "" || component == "*" {
		return "*"
	}

	// Keep only valid CPE characters
	re := regexp.MustCompile(`[^a-zA-Z0-9\-\.\*]`)
	component = re.ReplaceAllString(component, "-")

	// Remove leading/trailing dashes
	component = strings.Trim(component, "-")

	// If we ended up with nothing, return wildcard
	if component == "" {
		return "*"
	}

	return component
}
