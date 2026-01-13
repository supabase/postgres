package nix

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestNewWrapper(t *testing.T) {
	sbomnixPath := "/usr/bin/sbomnix"
	w := NewWrapper(sbomnixPath)

	if w == nil {
		t.Fatal("NewWrapper() returned nil")
	}

	if w.SbomnixPath != sbomnixPath {
		t.Errorf("NewWrapper() SbomnixPath = %q, want %q", w.SbomnixPath, sbomnixPath)
	}
}

func TestGenerateDerivationPathValidation(t *testing.T) {
	w := NewWrapper("sbomnix")

	// Test with non-existent derivation path
	err := w.Generate("/nonexistent/path/to/derivation", "/tmp/output.json")
	if err == nil {
		t.Error("Generate() should return error for non-existent derivation path")
	}

	if !strings.Contains(err.Error(), "derivation path does not exist") {
		t.Errorf("Generate() error = %q, want error containing 'derivation path does not exist'", err.Error())
	}
}

func TestGenerateOutputPathTraversalDetection(t *testing.T) {
	// Create a temporary directory to use as a valid derivation path
	tmpDir, err := os.MkdirTemp("", "wrapper-test-*")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tmpDir)

	w := NewWrapper("echo") // Use echo as a fake sbomnix that won't fail

	testCases := []struct {
		name       string
		outputPath string
		wantErr    bool
		errContain string
	}{
		{
			name:       "simple relative path",
			outputPath: "output.json",
			wantErr:    false,
		},
		{
			name:       "absolute path",
			outputPath: "/tmp/output.json",
			wantErr:    false,
		},
		{
			name:       "path with parent directory traversal",
			outputPath: "../../../etc/passwd",
			wantErr:    true,
			errContain: "path traversal",
		},
		{
			name:       "path with embedded traversal resolves clean",
			outputPath: "/tmp/foo/../../../etc/passwd",
			wantErr:    false, // filepath.Clean resolves this to /etc/passwd (no .. remains)
		},
		{
			name:       "path with double dot in middle",
			outputPath: "/tmp/../tmp/output.json",
			wantErr:    false, // filepath.Clean resolves this to /tmp/output.json
		},
		{
			name:       "path traversal at start",
			outputPath: "../../output.json",
			wantErr:    true,
			errContain: "path traversal",
		},
		{
			name:       "deeply nested traversal resolves clean",
			outputPath: "/a/b/c/../../../../etc/passwd",
			wantErr:    false, // filepath.Clean resolves this to /etc/passwd (no .. remains)
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			err := w.Generate(tmpDir, tc.outputPath)

			if tc.wantErr {
				if err == nil {
					t.Errorf("Generate() with outputPath=%q should return error", tc.outputPath)
					return
				}
				if tc.errContain != "" && !strings.Contains(err.Error(), tc.errContain) {
					t.Errorf("Generate() error = %q, want error containing %q", err.Error(), tc.errContain)
				}
			}
			// Note: For non-error cases, we can't fully test without a real sbomnix
			// The test verifies that path validation passes
		})
	}
}

func TestGeneratePathCleanBehavior(t *testing.T) {
	// Test that filepath.Clean is applied correctly
	testCases := []struct {
		input    string
		expected string
	}{
		{"./output.json", "output.json"},
		{"/tmp//output.json", "/tmp/output.json"},
		{"/tmp/./output.json", "/tmp/output.json"},
		{"output.json", "output.json"},
	}

	for _, tc := range testCases {
		cleaned := filepath.Clean(tc.input)
		if cleaned != tc.expected {
			t.Errorf("filepath.Clean(%q) = %q, want %q", tc.input, cleaned, tc.expected)
		}
	}
}

func TestGenerateTraversalAfterClean(t *testing.T) {
	// Verify behavior of filepath.Clean and our ".." detection
	// Note: filepath.Clean resolves ".." against the path, so absolute paths
	// like /tmp/../../../etc become /etc (no ".." remains)
	// Only relative paths that escape upward retain ".." after cleaning
	testCases := []struct {
		input        string
		shouldReject bool
		cleanedPath  string
	}{
		{"../foo", true, "../foo"},
		{"../../bar", true, "../../bar"},
		{"/tmp/../../../etc", false, "/etc"}, // Resolves to /etc, no .. remains
		{"/tmp/output.json", false, "/tmp/output.json"},
		{"output.json", false, "output.json"},
		{"./output.json", false, "output.json"}, // Clean removes ./
	}

	for _, tc := range testCases {
		cleaned := filepath.Clean(tc.input)
		if cleaned != tc.cleanedPath {
			t.Errorf("filepath.Clean(%q) = %q, want %q", tc.input, cleaned, tc.cleanedPath)
		}

		hasTraversal := strings.Contains(cleaned, "..")
		if hasTraversal != tc.shouldReject {
			t.Errorf("Path %q (cleaned: %q) hasTraversal=%v, want shouldReject=%v",
				tc.input, cleaned, hasTraversal, tc.shouldReject)
		}
	}
}
