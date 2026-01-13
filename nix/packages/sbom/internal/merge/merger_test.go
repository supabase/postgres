package merge

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/supabase/postgres/nix/packages/sbom/internal/spdx"
)

func TestNewMerger(t *testing.T) {
	m := NewMerger()
	if m == nil {
		t.Fatal("NewMerger() returned nil")
	}
}

func TestSanitizeCPEComponent(t *testing.T) {
	testCases := []struct {
		input    string
		expected string
	}{
		{"simple", "simple"},
		{"with-dash", "with-dash"},
		{"with_underscore", "with-underscore"}, // underscore replaced with dash
		{"with.dot", "with.dot"},
		{"MixedCase", "MixedCase"},
		{"123numeric", "123numeric"},
		{"", "*"},
		{"*", "*"},
		{"with space", "with-space"},
		{"with@symbol", "with-symbol"},
		{"special!chars#here", "special-chars-here"},
		{"-leading-dash", "leading-dash"},
		{"trailing-dash-", "trailing-dash"},
		{"-both-dashes-", "both-dashes"},
		{"pg_cron", "pg-cron"},
		{"multiple___underscores", "multiple---underscores"},
	}

	for _, tc := range testCases {
		t.Run(tc.input, func(t *testing.T) {
			result := sanitizeCPEComponent(tc.input)
			if result != tc.expected {
				t.Errorf("sanitizeCPEComponent(%q) = %q, want %q", tc.input, result, tc.expected)
			}
		})
	}
}

func TestRenumberSPDXID(t *testing.T) {
	m := NewMerger()

	testCases := []struct {
		originalID string
		prefix     string
		expected   string
	}{
		{"SPDXRef-Package-1", "Ubuntu", "SPDXRef-Ubuntu-Package-1"},
		{"SPDXRef-Package-1", "Nix", "SPDXRef-Nix-Package-1"},
		{"SPDXRef-foo-bar", "Test", "SPDXRef-Test-foo-bar"},
		{"SPDXRef-123", "Prefix", "SPDXRef-Prefix-123"},
		{"InvalidID", "Test", "SPDXRef-Test-InvalidID"},
	}

	for _, tc := range testCases {
		t.Run(tc.originalID+"_"+tc.prefix, func(t *testing.T) {
			result := m.renumberSPDXID(tc.originalID, tc.prefix)
			if result != tc.expected {
				t.Errorf("renumberSPDXID(%q, %q) = %q, want %q", tc.originalID, tc.prefix, result, tc.expected)
			}
		})
	}
}

func TestFixCPEFormat(t *testing.T) {
	m := NewMerger()

	testCases := []struct {
		name     string
		input    string
		expected string
	}{
		{
			name:     "already valid CPE",
			input:    "cpe:2.3:a:vendor:product:1.0:*:*:*:*:*:*:*",
			expected: "cpe:2.3:a:vendor:product:1.0:*:*:*:*:*:*:*",
		},
		{
			name:     "duplicate vendor/product from sbomnix",
			input:    "cpe:2.3:a:pg_cron:pg_cron::*:*:*:*:*:*:*",
			expected: "cpe:2.3:a:pg-cron:pg-cron:*:*:*:*:*:*:*:*",
		},
		{
			name:     "not a CPE",
			input:    "not-a-cpe",
			expected: "not-a-cpe",
		},
		{
			name:     "too short",
			input:    "cpe:2.3:a",
			expected: "cpe:2.3:a",
		},
		{
			name:     "with version",
			input:    "cpe:2.3:a:vendor:product:2.0:*:*:*:*:*:*:*",
			expected: "cpe:2.3:a:vendor:product:2.0:*:*:*:*:*:*:*",
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			result := m.fixCPEFormat(tc.input)
			if result != tc.expected {
				t.Errorf("fixCPEFormat(%q) = %q, want %q", tc.input, result, tc.expected)
			}
		})
	}
}

func TestCleanExternalRefs(t *testing.T) {
	m := NewMerger()

	refs := []spdx.ExternalRef{
		{
			Category: "SECURITY",
			Type:     "cpe23Type",
			Locator:  "cpe:2.3:a:vendor:product:1.0:*:*:*:*:*:*:*",
		},
		{
			Category: "PACKAGE-MANAGER",
			Type:     "purl",
			Locator:  "pkg:npm/package@1.0.0",
		},
	}

	cleaned := m.cleanExternalRefs(refs)

	if len(cleaned) != 2 {
		t.Fatalf("cleanExternalRefs() returned %d refs, want 2", len(cleaned))
	}

	// Non-CPE refs should be unchanged
	if cleaned[1].Locator != "pkg:npm/package@1.0.0" {
		t.Errorf("purl ref was modified: %q", cleaned[1].Locator)
	}
}

func TestMergeCreators(t *testing.T) {
	m := NewMerger()

	ubuntuDoc := &spdx.Document{
		CreationInfo: spdx.CreationInfo{
			Creators: []string{"Tool: ubuntu-generator", "Organization: Ubuntu"},
		},
	}

	nixDoc := &spdx.Document{
		CreationInfo: spdx.CreationInfo{
			Creators: []string{"Tool: sbomnix", "Organization: Nix"},
		},
	}

	creators := m.mergeCreators(ubuntuDoc, nixDoc)

	// Should contain all creators plus merger tool
	expectedCreators := map[string]bool{
		"Tool: ubuntu-generator":           true,
		"Organization: Ubuntu":             true,
		"Tool: sbomnix":                    true,
		"Organization: Nix":                true,
		"Tool: ubuntu-nix-sbom-merger-1.0": true,
	}

	if len(creators) != len(expectedCreators) {
		t.Errorf("mergeCreators() returned %d creators, want %d", len(creators), len(expectedCreators))
	}

	for _, creator := range creators {
		if !expectedCreators[creator] {
			t.Errorf("Unexpected creator: %q", creator)
		}
	}
}

func TestMergeCreatorsNoDuplicates(t *testing.T) {
	m := NewMerger()

	// Both documents have the same creator
	ubuntuDoc := &spdx.Document{
		CreationInfo: spdx.CreationInfo{
			Creators: []string{"Tool: shared-tool"},
		},
	}

	nixDoc := &spdx.Document{
		CreationInfo: spdx.CreationInfo{
			Creators: []string{"Tool: shared-tool"},
		},
	}

	creators := m.mergeCreators(ubuntuDoc, nixDoc)

	// Count occurrences
	count := 0
	for _, c := range creators {
		if c == "Tool: shared-tool" {
			count++
		}
	}

	if count != 1 {
		t.Errorf("Duplicate creator found %d times, want 1", count)
	}
}

func createTestSBOMFile(t *testing.T, dir, name string, doc *spdx.Document) string {
	t.Helper()
	path := filepath.Join(dir, name)
	data, err := json.MarshalIndent(doc, "", "  ")
	if err != nil {
		t.Fatalf("Failed to marshal document: %v", err)
	}
	if err := os.WriteFile(path, data, 0644); err != nil {
		t.Fatalf("Failed to write file: %v", err)
	}
	return path
}

func TestMerge(t *testing.T) {
	tmpDir, err := os.MkdirTemp("", "merge-test-*")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tmpDir)

	// Create Ubuntu SBOM
	ubuntuDoc := &spdx.Document{
		SPDXVersion:       "SPDX-2.3",
		DataLicense:       "CC0-1.0",
		SPDXID:            "SPDXRef-DOCUMENT",
		Name:              "Ubuntu-SBOM",
		DocumentNamespace: "https://example.com/ubuntu",
		CreationInfo: spdx.CreationInfo{
			Created:  "2024-01-01T00:00:00Z",
			Creators: []string{"Tool: ubuntu-generator"},
		},
		Packages: []spdx.Package{
			{
				SPDXID:           "SPDXRef-Ubuntu-System",
				Name:             "Ubuntu-System",
				DownloadLocation: "NOASSERTION",
				LicenseConcluded: "NOASSERTION",
				LicenseDeclared:  "NOASSERTION",
				CopyrightText:    "NOASSERTION",
			},
			{
				SPDXID:           "SPDXRef-Ubuntu-Package-1-curl",
				Name:             "curl",
				PackageVersion:   "7.68.0",
				DownloadLocation: "NOASSERTION",
				LicenseConcluded: "MIT",
				LicenseDeclared:  "MIT",
				CopyrightText:    "NOASSERTION",
			},
		},
		Relationships: []spdx.Relationship{
			{
				SPDXElementID:      "SPDXRef-Ubuntu-System",
				RelatedSPDXElement: "SPDXRef-Ubuntu-Package-1-curl",
				RelationshipType:   "CONTAINS",
			},
		},
	}

	// Create Nix SBOM
	nixDoc := &spdx.Document{
		SPDXVersion:       "SPDX-2.3",
		DataLicense:       "CC0-1.0",
		SPDXID:            "SPDXRef-DOCUMENT",
		Name:              "Nix-SBOM",
		DocumentNamespace: "https://example.com/nix",
		CreationInfo: spdx.CreationInfo{
			Created:  "2024-01-01T00:00:00Z",
			Creators: []string{"Tool: sbomnix"},
		},
		Packages: []spdx.Package{
			{
				SPDXID:           "SPDXRef-Package-1",
				Name:             "openssl",
				PackageVersion:   "3.0.0",
				DownloadLocation: "NOASSERTION",
				LicenseConcluded: "Apache-2.0",
				LicenseDeclared:  "Apache-2.0",
				CopyrightText:    "NOASSERTION",
			},
		},
		Relationships: []spdx.Relationship{},
	}

	ubuntuPath := createTestSBOMFile(t, tmpDir, "ubuntu.json", ubuntuDoc)
	nixPath := createTestSBOMFile(t, tmpDir, "nix.json", nixDoc)

	m := NewMerger()
	mergedDoc, err := m.Merge(ubuntuPath, nixPath)
	if err != nil {
		t.Fatalf("Merge() error: %v", err)
	}

	// Verify merged document properties
	if mergedDoc.SPDXVersion != "SPDX-2.3" {
		t.Errorf("SPDXVersion = %q, want SPDX-2.3", mergedDoc.SPDXVersion)
	}

	if !strings.HasPrefix(mergedDoc.Name, "Ubuntu-Nix-System-SBOM-") {
		t.Errorf("Name = %q, want prefix 'Ubuntu-Nix-System-SBOM-'", mergedDoc.Name)
	}

	// Should have: System root + 1 Ubuntu package (curl, not System) + 1 Nix package (openssl)
	expectedPackageCount := 3
	if len(mergedDoc.Packages) != expectedPackageCount {
		t.Errorf("Package count = %d, want %d", len(mergedDoc.Packages), expectedPackageCount)
		for i, pkg := range mergedDoc.Packages {
			t.Logf("  Package %d: %s (%s)", i, pkg.SPDXID, pkg.Name)
		}
	}

	// Verify root package exists
	hasRoot := false
	for _, pkg := range mergedDoc.Packages {
		if pkg.SPDXID == "SPDXRef-System" {
			hasRoot = true
			break
		}
	}
	if !hasRoot {
		t.Error("Merged document missing root System package")
	}

	// Verify Nix package has been prefixed
	hasNixPkg := false
	for _, pkg := range mergedDoc.Packages {
		if strings.HasPrefix(pkg.SPDXID, "SPDXRef-Nix-") && pkg.Name == "openssl" {
			hasNixPkg = true
			break
		}
	}
	if !hasNixPkg {
		t.Error("Nix package not found with proper prefix")
	}
}

func TestMergeInvalidUbuntuPath(t *testing.T) {
	m := NewMerger()

	_, err := m.Merge("/nonexistent/ubuntu.json", "/nonexistent/nix.json")
	if err == nil {
		t.Error("Merge() should return error for non-existent files")
	}

	if !strings.Contains(err.Error(), "Ubuntu SBOM") {
		t.Errorf("Error should mention Ubuntu SBOM: %v", err)
	}
}

func TestMergeInvalidNixPath(t *testing.T) {
	tmpDir, err := os.MkdirTemp("", "merge-test-*")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tmpDir)

	ubuntuDoc := &spdx.Document{
		SPDXVersion: "SPDX-2.3",
		Packages:    []spdx.Package{},
	}
	ubuntuPath := createTestSBOMFile(t, tmpDir, "ubuntu.json", ubuntuDoc)

	m := NewMerger()
	_, err = m.Merge(ubuntuPath, "/nonexistent/nix.json")
	if err == nil {
		t.Error("Merge() should return error for non-existent Nix file")
	}

	if !strings.Contains(err.Error(), "Nix SBOM") {
		t.Errorf("Error should mention Nix SBOM: %v", err)
	}
}

func TestMergeInvalidJSON(t *testing.T) {
	tmpDir, err := os.MkdirTemp("", "merge-test-*")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tmpDir)

	// Create invalid JSON file
	invalidPath := filepath.Join(tmpDir, "invalid.json")
	if err := os.WriteFile(invalidPath, []byte("not valid json"), 0644); err != nil {
		t.Fatalf("Failed to write invalid file: %v", err)
	}

	validDoc := &spdx.Document{SPDXVersion: "SPDX-2.3"}
	validPath := createTestSBOMFile(t, tmpDir, "valid.json", validDoc)

	m := NewMerger()

	// Invalid Ubuntu file
	_, err = m.Merge(invalidPath, validPath)
	if err == nil {
		t.Error("Merge() should return error for invalid JSON")
	}
}

func TestSave(t *testing.T) {
	tmpDir, err := os.MkdirTemp("", "save-test-*")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tmpDir)

	doc := &spdx.Document{
		SPDXVersion:       "SPDX-2.3",
		DataLicense:       "CC0-1.0",
		SPDXID:            "SPDXRef-DOCUMENT",
		Name:              "Test-SBOM",
		DocumentNamespace: "https://example.com/test",
		Packages:          []spdx.Package{},
		Relationships:     []spdx.Relationship{},
	}

	m := NewMerger()
	outputPath := filepath.Join(tmpDir, "output.json")

	if err := m.Save(doc, outputPath); err != nil {
		t.Fatalf("Save() error: %v", err)
	}

	// Verify file exists and is valid JSON
	data, err := os.ReadFile(outputPath)
	if err != nil {
		t.Fatalf("Failed to read saved file: %v", err)
	}

	var loadedDoc spdx.Document
	if err := json.Unmarshal(data, &loadedDoc); err != nil {
		t.Fatalf("Saved file is not valid JSON: %v", err)
	}

	if loadedDoc.SPDXVersion != doc.SPDXVersion {
		t.Errorf("Loaded SPDXVersion = %q, want %q", loadedDoc.SPDXVersion, doc.SPDXVersion)
	}
}

func TestSaveInvalidPath(t *testing.T) {
	doc := &spdx.Document{SPDXVersion: "SPDX-2.3"}
	m := NewMerger()

	err := m.Save(doc, "/nonexistent/directory/output.json")
	if err == nil {
		t.Error("Save() should return error for invalid path")
	}
}

func TestLoadDocument(t *testing.T) {
	tmpDir, err := os.MkdirTemp("", "load-test-*")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tmpDir)

	originalDoc := &spdx.Document{
		SPDXVersion:       "SPDX-2.3",
		DataLicense:       "CC0-1.0",
		SPDXID:            "SPDXRef-DOCUMENT",
		Name:              "Test-Document",
		DocumentNamespace: "https://example.com/test",
		CreationInfo: spdx.CreationInfo{
			Created:  "2024-01-01T00:00:00Z",
			Creators: []string{"Tool: test"},
		},
		Packages: []spdx.Package{
			{
				SPDXID: "SPDXRef-Package-1",
				Name:   "test-package",
			},
		},
	}

	path := createTestSBOMFile(t, tmpDir, "test.json", originalDoc)

	m := NewMerger()
	loadedDoc, err := m.loadDocument(path)
	if err != nil {
		t.Fatalf("loadDocument() error: %v", err)
	}

	if loadedDoc.Name != originalDoc.Name {
		t.Errorf("Name = %q, want %q", loadedDoc.Name, originalDoc.Name)
	}
	if len(loadedDoc.Packages) != len(originalDoc.Packages) {
		t.Errorf("Packages count = %d, want %d", len(loadedDoc.Packages), len(originalDoc.Packages))
	}
}

func TestMergeDocumentNamespaceUnique(t *testing.T) {
	tmpDir, err := os.MkdirTemp("", "merge-test-*")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tmpDir)

	ubuntuDoc := &spdx.Document{
		SPDXVersion: "SPDX-2.3",
		CreationInfo: spdx.CreationInfo{
			Creators: []string{},
		},
		Packages: []spdx.Package{},
	}
	nixDoc := &spdx.Document{
		SPDXVersion: "SPDX-2.3",
		CreationInfo: spdx.CreationInfo{
			Creators: []string{},
		},
		Packages: []spdx.Package{},
	}

	ubuntuPath := createTestSBOMFile(t, tmpDir, "ubuntu.json", ubuntuDoc)
	nixPath := createTestSBOMFile(t, tmpDir, "nix.json", nixDoc)

	m := NewMerger()

	// Generate multiple merged documents
	namespaces := make(map[string]bool)
	for i := 0; i < 10; i++ {
		merged, err := m.Merge(ubuntuPath, nixPath)
		if err != nil {
			t.Fatalf("Merge() error: %v", err)
		}

		if namespaces[merged.DocumentNamespace] {
			t.Errorf("Duplicate DocumentNamespace generated: %s", merged.DocumentNamespace)
		}
		namespaces[merged.DocumentNamespace] = true
	}
}

func BenchmarkMerge(b *testing.B) {
	tmpDir, err := os.MkdirTemp("", "merge-bench-*")
	if err != nil {
		b.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tmpDir)

	// Create documents with many packages
	ubuntuDoc := &spdx.Document{
		SPDXVersion: "SPDX-2.3",
		CreationInfo: spdx.CreationInfo{
			Creators: []string{"Tool: ubuntu-generator"},
		},
		Packages: make([]spdx.Package, 100),
	}
	for i := 0; i < 100; i++ {
		ubuntuDoc.Packages[i] = spdx.Package{
			SPDXID: "SPDXRef-Ubuntu-Package-" + string(rune('0'+i%10)),
			Name:   "package-" + string(rune('0'+i%10)),
		}
	}

	nixDoc := &spdx.Document{
		SPDXVersion: "SPDX-2.3",
		CreationInfo: spdx.CreationInfo{
			Creators: []string{"Tool: sbomnix"},
		},
		Packages: make([]spdx.Package, 100),
	}
	for i := 0; i < 100; i++ {
		nixDoc.Packages[i] = spdx.Package{
			SPDXID: "SPDXRef-Package-" + string(rune('0'+i%10)),
			Name:   "nix-package-" + string(rune('0'+i%10)),
		}
	}

	ubuntuData, _ := json.Marshal(ubuntuDoc)
	nixData, _ := json.Marshal(nixDoc)

	ubuntuPath := filepath.Join(tmpDir, "ubuntu.json")
	nixPath := filepath.Join(tmpDir, "nix.json")
	os.WriteFile(ubuntuPath, ubuntuData, 0644)
	os.WriteFile(nixPath, nixData, 0644)

	m := NewMerger()

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_, err := m.Merge(ubuntuPath, nixPath)
		if err != nil {
			b.Fatalf("Merge() error: %v", err)
		}
	}
}
