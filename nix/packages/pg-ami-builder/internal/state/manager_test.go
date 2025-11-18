package state

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestSaveState(t *testing.T) {
	tmpDir := t.TempDir()
	stateFile := filepath.Join(tmpDir, "state.json")

	state := &State{
		InstanceID:      "i-1234567890abcdef0",
		Phase:           "phase1",
		ExecutionID:     "1731672000-15",
		Region:          "us-east-1",
		PostgresVersion: "15",
		Timestamp:       time.Now().Format(time.RFC3339),
		GitSHA:          "abc123",
	}

	err := SaveState(stateFile, state)
	if err != nil {
		t.Fatalf("SaveState failed: %v", err)
	}

	if _, err := os.Stat(stateFile); os.IsNotExist(err) {
		t.Fatal("State file was not created")
	}
}

func TestLoadState(t *testing.T) {
	tmpDir := t.TempDir()
	stateFile := filepath.Join(tmpDir, "state.json")

	original := &State{
		InstanceID:      "i-test123",
		Phase:           "phase2",
		ExecutionID:     "exec-1",
		Region:          "us-west-2",
		PostgresVersion: "16",
		GitSHA:          "def456",
	}

	if err := SaveState(stateFile, original); err != nil {
		t.Fatalf("SaveState failed: %v", err)
	}

	loaded, err := LoadState(stateFile)
	if err != nil {
		t.Fatalf("LoadState failed: %v", err)
	}

	if loaded.InstanceID != original.InstanceID {
		t.Errorf("InstanceID mismatch: got %s, want %s", loaded.InstanceID, original.InstanceID)
	}
	if loaded.Phase != original.Phase {
		t.Errorf("Phase mismatch: got %s, want %s", loaded.Phase, original.Phase)
	}
}

func TestGetDefaultStateFile(t *testing.T) {
	path, err := GetDefaultStateFile()
	if err != nil {
		// Skip if we can't create the state directory (e.g., in Nix build sandbox)
		t.Skipf("GetDefaultStateFile failed (expected in sandboxed environments): %v", err)
	}

	if path == "" {
		t.Fatal("GetDefaultStateFile returned empty path")
	}

	if !filepath.IsAbs(path) {
		t.Errorf("Expected absolute path, got %s", path)
	}
}
