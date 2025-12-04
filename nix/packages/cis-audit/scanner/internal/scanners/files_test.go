package scanners

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	"github.com/supabase/ubuntu-cis-audit/scanner/internal/config"
	"github.com/supabase/ubuntu-cis-audit/scanner/internal/spec"
)

func TestFileScanner_BasicScan(t *testing.T) {
	tmpDir := t.TempDir()

	// Create test files with known permissions
	os.WriteFile(filepath.Join(tmpDir, "file1.txt"), []byte("data"), 0644)
	os.WriteFile(filepath.Join(tmpDir, "file2.sh"), []byte("script"), 0755)

	subdir := filepath.Join(tmpDir, "subdir")
	os.Mkdir(subdir, 0755)
	os.WriteFile(filepath.Join(subdir, "file3"), []byte("test"), 0600)

	scanner := &FileScanner{rootPath: tmpDir}
	writer := spec.NewTestWriter()

	opts := ScanOptions{
		Writer: writer,
		Config: &config.Config{
			Paths: []string{}, // No exclusions
		},
		Logger: testLogger(),
	}

	_, err := scanner.Scan(context.Background(), opts)
	if err != nil {
		t.Fatalf("Scan failed: %v", err)
	}

	results := writer.GetFileResults()
	if len(results) != 3 {
		t.Errorf("Expected 3 files, got %d", len(results))
	}

	// Verify file2.sh has correct mode
	for _, r := range results {
		if filepath.Base(r.Path) == "file2.sh" {
			if r.Mode != "0755" {
				t.Errorf("Expected mode 0755, got %s", r.Mode)
			}
		}
	}
}

func TestFileScanner_Exclusions(t *testing.T) {
	tmpDir := t.TempDir()

	proc := filepath.Join(tmpDir, "proc")
	etc := filepath.Join(tmpDir, "etc")
	os.Mkdir(proc, 0755)
	os.Mkdir(etc, 0755)

	os.WriteFile(filepath.Join(proc, "cpuinfo"), []byte("test"), 0644)
	os.WriteFile(filepath.Join(etc, "passwd"), []byte("test"), 0644)

	scanner := &FileScanner{rootPath: tmpDir}
	writer := spec.NewTestWriter()

	opts := ScanOptions{
		Writer: writer,
		Config: &config.Config{
			Paths: []string{filepath.Join(tmpDir, "proc") + "/*"},
		},
		Logger: testLogger(),
	}

	scanner.Scan(context.Background(), opts)

	results := writer.GetFileResults()

	// Should only have /etc/passwd, not /proc/cpuinfo
	if len(results) != 1 {
		t.Errorf("Expected 1 file (excluded proc), got %d", len(results))
	}
}
