package ubuntu

import (
	"bufio"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"regexp"
	"strings"
	"time"

	"github.com/supabase/postgres/nix/packages/sbom/internal/spdx"
)

type DpkgPackage struct {
	Name         string
	Version      string
	Architecture string
	Status       string
	Maintainer   string
	Homepage     string
	Description  string
	License      string
	Copyright    string
}

type Generator struct {
	IncludeFiles bool
	ShowProgress bool
}

func NewGenerator(includeFiles, showProgress bool) *Generator {
	return &Generator{
		IncludeFiles: includeFiles,
		ShowProgress: showProgress,
	}
}

func (g *Generator) Generate() (*spdx.Document, error) {
	packages, err := g.getInstalledPackages()
	if err != nil {
		return nil, fmt.Errorf("failed to get packages: %w", err)
	}

	doc := &spdx.Document{
		SPDXVersion:       "SPDX-2.3",
		DataLicense:       "CC0-1.0",
		SPDXID:            "SPDXRef-DOCUMENT",
		Name:              fmt.Sprintf("Ubuntu-System-SBOM-%s", time.Now().Format("2006-01-02")),
		DocumentNamespace: fmt.Sprintf("https://sbom.ubuntu.system/%s", generateUUID()),
		CreationInfo: spdx.CreationInfo{
			Created:            time.Now().UTC().Format(time.RFC3339),
			Creators:           []string{"Tool: ubuntu-sbom-generator-1.0"},
			LicenseListVersion: "3.20",
		},
		Packages:      []spdx.Package{},
		Relationships: []spdx.Relationship{},
	}

	// Add root package representing the Ubuntu system
	rootPkg := spdx.Package{
		SPDXID:           "SPDXRef-Ubuntu-System",
		Name:             "Ubuntu-System",
		DownloadLocation: "NOASSERTION",
		FilesAnalyzed:    false,
		LicenseConcluded: "NOASSERTION",
		LicenseDeclared:  "NOASSERTION",
		CopyrightText:    "NOASSERTION",
	}
	doc.Packages = append(doc.Packages, rootPkg)

	// Process each package
	for i, pkg := range packages {
		if g.ShowProgress && i%100 == 0 {
			fmt.Printf("Processing package %d/%d...\n", i+1, len(packages))
		}

		spdxPkg := g.packageToSPDX(pkg, i+1)
		doc.Packages = append(doc.Packages, spdxPkg)

		// Add relationship
		doc.Relationships = append(doc.Relationships, spdx.Relationship{
			SPDXElementID:      "SPDXRef-Ubuntu-System",
			RelatedSPDXElement: spdxPkg.SPDXID,
			RelationshipType:   "CONTAINS",
		})
	}

	// Add document describes relationship
	doc.Relationships = append(doc.Relationships, spdx.Relationship{
		SPDXElementID:      "SPDXRef-DOCUMENT",
		RelatedSPDXElement: "SPDXRef-Ubuntu-System",
		RelationshipType:   "DESCRIBES",
	})

	return doc, nil
}

func (g *Generator) getInstalledPackages() ([]DpkgPackage, error) {
	cmd := exec.Command("dpkg-query", "-W", "-f=${Package}\t${Version}\t${Architecture}\t${Status}\t${Maintainer}\t${Homepage}\t${Description}\n")
	output, err := cmd.Output()
	if err != nil {
		return nil, err
	}

	var packages []DpkgPackage
	scanner := bufio.NewScanner(strings.NewReader(string(output)))

	for scanner.Scan() {
		line := scanner.Text()
		parts := strings.Split(line, "\t")

		if len(parts) >= 7 && strings.Contains(parts[3], "installed") {
			pkg := DpkgPackage{
				Name:         parts[0],
				Version:      parts[1],
				Architecture: parts[2],
				Status:       parts[3],
				Maintainer:   parts[4],
				Homepage:     parts[5],
				Description:  parts[6],
			}

			// Try to get license information
			pkg.License, pkg.Copyright = g.getPackageLicense(pkg.Name)

			packages = append(packages, pkg)
		}
	}

	fmt.Printf("Found %d installed packages\n", len(packages))
	return packages, nil
}

func (g *Generator) getPackageLicense(packageName string) (string, string) {
	copyrightPath := fmt.Sprintf("/usr/share/doc/%s/copyright", packageName)

	content, err := os.ReadFile(copyrightPath)
	if err != nil {
		return "NOASSERTION", "NOASSERTION"
	}

	text := string(content)

	// Extract license
	license := "NOASSERTION"
	licenseRe := regexp.MustCompile(`(?i)License:\s*(.+?)(?:\n\n|\n[A-Z]|\z)`)
	if matches := licenseRe.FindStringSubmatch(text); len(matches) > 1 {
		license = normalizeLicense(strings.TrimSpace(matches[1]))
	}

	// Get first 200 chars of copyright or NOASSERTION
	copyright := "NOASSERTION"
	if len(text) > 0 {
		if len(text) > 200 {
			copyright = text[:200] + "..."
		} else {
			copyright = text
		}
	}

	return license, copyright
}

func (g *Generator) packageToSPDX(pkg DpkgPackage, id int) spdx.Package {
	spdxPkg := spdx.Package{
		SPDXID:           fmt.Sprintf("SPDXRef-Ubuntu-Package-%d-%s", id, sanitizeName(pkg.Name)),
		Name:             pkg.Name,
		PackageVersion:   pkg.Version,
		DownloadLocation: "NOASSERTION",
		FilesAnalyzed:    false,
		LicenseConcluded: pkg.License,
		LicenseDeclared:  pkg.License,
		CopyrightText:    pkg.Copyright,
		Description:      pkg.Description,
	}

	if pkg.Homepage != "" && pkg.Homepage != "(none)" {
		spdxPkg.HomePage = pkg.Homepage
	}

	if pkg.Maintainer != "" && pkg.Maintainer != "(none)" {
		spdxPkg.Supplier = fmt.Sprintf("Organization: %s", pkg.Maintainer)
	}

	// Add external reference for the package
	spdxPkg.ExternalRefs = []spdx.ExternalRef{
		{
			Category: "PACKAGE-MANAGER",
			Type:     "purl",
			Locator:  fmt.Sprintf("pkg:deb/ubuntu/%s@%s?arch=%s", pkg.Name, pkg.Version, pkg.Architecture),
		},
	}

	// If include-files is set, calculate package verification
	if g.IncludeFiles {
		if checksum := g.calculatePackageChecksum(pkg.Name); checksum != "" {
			spdxPkg.Checksums = []spdx.Checksum{
				{
					Algorithm: "SHA256",
					Value:     checksum,
				},
			}
		}
	}

	return spdxPkg
}

func (g *Generator) calculatePackageChecksum(packageName string) string {
	cmd := exec.Command("dpkg", "-L", packageName)
	output, err := cmd.Output()
	if err != nil {
		return ""
	}

	h := sha256.New()
	scanner := bufio.NewScanner(strings.NewReader(string(output)))

	for scanner.Scan() {
		filePath := scanner.Text()
		if filePath == "" || strings.HasSuffix(filePath, "/") {
			continue
		}

		if fileHash := hashFile(filePath); fileHash != "" {
			h.Write([]byte(fileHash))
		}
	}

	return fmt.Sprintf("%x", h.Sum(nil))
}

func hashFile(path string) string {
	file, err := os.Open(path)
	if err != nil {
		return ""
	}
	defer file.Close()

	h := sha256.New()
	if _, err := io.Copy(h, file); err != nil {
		return ""
	}

	return fmt.Sprintf("%x", h.Sum(nil))
}

func (g *Generator) Save(doc *spdx.Document, outputPath string) error {
	file, err := os.Create(outputPath)
	if err != nil {
		return err
	}
	defer file.Close()

	encoder := json.NewEncoder(file)
	encoder.SetIndent("", "  ")

	return encoder.Encode(doc)
}

func normalizeLicense(license string) string {
	// Map common license strings to SPDX identifiers
	license = strings.TrimSpace(license)

	// If empty, return NOASSERTION
	if license == "" {
		return "NOASSERTION"
	}

	// Normalize to lowercase for case-insensitive matching
	licenseLower := strings.ToLower(license)

	// Check for known SPDX patterns (case-insensitive)
	replacements := map[string]string{
		"gpl-2":                       "GPL-2.0-only",
		"gpl-2+":                      "GPL-2.0-or-later",
		"gpl-3":                       "GPL-3.0-only",
		"gpl-3+":                      "GPL-3.0-or-later",
		"lgpl-2":                      "LGPL-2.0-only",
		"lgpl-2+":                     "LGPL-2.0-or-later",
		"lgpl-2.1":                    "LGPL-2.1-only",
		"lgpl-2.1+":                   "LGPL-2.1-or-later",
		"lgpl-3":                      "LGPL-3.0-only",
		"lgpl-3+":                     "LGPL-3.0-or-later",
		"apache-2":                    "Apache-2.0",
		"apache":                      "NOASSERTION",
		"bsd":                         "BSD-3-Clause",
		"mit/x11":                     "MIT",
		"expat":                       "MIT",
		"mit-1":                       "MIT",
		"mit-style":                   "MIT",
		"psf":                         "Python-2.0",
		"public-domain":               "NOASSERTION",
		"openldap-2.8":                "NOASSERTION",
		"hylafax":                     "NOASSERTION",
		"ubuntu-font-licence-1.0":     "Ubuntu-Font-1.0",
		"go":                          "NOASSERTION",
		"epl-1":                       "EPL-1.0",
		"dom4j":                       "NOASSERTION",
		"fastcgi":                     "NOASSERTION",
		"other":                       "NOASSERTION",
		"eclipse-public-license-v1.0": "EPL-1.0",
		"edl-1.0":                     "BSD-3-Clause",
		"nrl-2-clause":                "NOASSERTION",
		"tidy":                        "NOASSERTION",
		"purdue":                      "NOASSERTION",
		"mpl-2":                       "MPL-2.0",
	}

	// Check for exact match first (case-insensitive)
	if mapped, ok := replacements[licenseLower]; ok {
		return mapped
	}

	// Check for prefix match (case-insensitive)
	for old, new := range replacements {
		if strings.HasPrefix(licenseLower, old) {
			return new
		}
	}

	// Check if it looks like a valid SPDX identifier
	validSPDXPattern := regexp.MustCompile(`^[A-Za-z0-9.\-]+(\s+(AND|OR|WITH)\s+[A-Za-z0-9.\-]+)*$`)

	if validSPDXPattern.MatchString(license) {
		return license
	}

	// If it contains copyright statements, full sentences, or invalid characters, return NOASSERTION
	invalidPatterns := []string{
		"Copyright", "copyright", "Permission is hereby", "The files",
		"Formerly,", "build-aux", "Portions", "free software",
		"<", ">", "'", ",",
	}

	for _, pattern := range invalidPatterns {
		if strings.Contains(license, pattern) {
			return "NOASSERTION"
		}
	}

	// If license string is longer than 50 chars, it's probably license text
	if len(license) > 50 {
		return "NOASSERTION"
	}

	// Default: if we can't confidently map it, use NOASSERTION
	return "NOASSERTION"
}

func sanitizeName(name string) string {
	// Replace non-alphanumeric characters with hyphens for SPDX IDs
	re := regexp.MustCompile(`[^a-zA-Z0-9-.]`)
	return re.ReplaceAllString(name, "-")
}

func generateUUID() string {
	// Simple UUID v4 generation
	b := make([]byte, 16)
	for i := range b {
		b[i] = byte(time.Now().UnixNano() & 0xff)
	}

	return fmt.Sprintf("%x-%x-%x-%x-%x",
		b[0:4], b[4:6], b[6:8], b[8:10], b[10:])
}
