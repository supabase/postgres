package config

import (
	"os"
	"path/filepath"
	"testing"
)

func TestLoad_Defaults(t *testing.T) {
	cfg, err := Load("", CLIOptions{})
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}

	// Verify default path exclusions are present
	expectedPaths := []string{"/proc/*", "/sys/*", "/dev/*"}
	for _, path := range expectedPaths {
		found := false
		for _, excluded := range cfg.Paths {
			if excluded == path {
				found = true
				break
			}
		}
		if !found {
			t.Errorf("Expected default path exclusion %q not found", path)
		}
	}

	// Verify default kernel param exclusions are present
	expectedParams := []string{"fs.dentry-state", "kernel.random.uuid"}
	for _, param := range expectedParams {
		found := false
		for _, excluded := range cfg.KernelParams {
			if excluded == param {
				found = true
				break
			}
		}
		if !found {
			t.Errorf("Expected default kernel param exclusion %q not found", param)
		}
	}

	// Verify default disabled scanners are present
	expectedDisabled := []string{"port", "process"}
	for _, scanner := range expectedDisabled {
		found := false
		for _, disabled := range cfg.DisabledScanners {
			if disabled == scanner {
				found = true
				break
			}
		}
		if !found {
			t.Errorf("Expected default disabled scanner %q not found", scanner)
		}
	}
}

func TestLoad_ConfigFile(t *testing.T) {
	// Create a temporary config file
	tmpDir := t.TempDir()
	configPath := filepath.Join(tmpDir, "config.yaml")
	configContent := `
paths:
  - /custom/path/*
  - /another/path
kernelParams:
  - custom.param
disabledScanners:
  - custom_scanner
`
	if err := os.WriteFile(configPath, []byte(configContent), 0644); err != nil {
		t.Fatalf("Failed to create test config file: %v", err)
	}

	cfg, err := Load(configPath, CLIOptions{})
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}

	// Verify config file additions are present
	if !contains(cfg.Paths, "/custom/path/*") {
		t.Errorf("Expected custom path from config file not found")
	}
	if !contains(cfg.KernelParams, "custom.param") {
		t.Errorf("Expected custom kernel param from config file not found")
	}
	if !contains(cfg.DisabledScanners, "custom_scanner") {
		t.Errorf("Expected custom disabled scanner from config file not found")
	}

	// Verify defaults are still present
	if !contains(cfg.Paths, "/proc/*") {
		t.Errorf("Expected default path exclusion not found after loading config file")
	}
}

func TestLoad_CLIOverrides(t *testing.T) {
	// Create a temporary config file that disables ports and processes
	tmpDir := t.TempDir()
	configPath := filepath.Join(tmpDir, "config.yaml")
	configContent := `
disabledScanners:
  - port
  - process
`
	if err := os.WriteFile(configPath, []byte(configContent), 0644); err != nil {
		t.Fatalf("Failed to create test config file: %v", err)
	}

	// Test IncludePorts override
	cfg, err := Load(configPath, CLIOptions{IncludePorts: true})
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}
	if contains(cfg.DisabledScanners, "port") {
		t.Errorf("port scanner should not be disabled when IncludePorts is true")
	}
	if !contains(cfg.DisabledScanners, "process") {
		t.Errorf("process scanner should still be disabled")
	}

	// Test IncludeProcesses override
	cfg, err = Load(configPath, CLIOptions{IncludeProcesses: true})
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}
	if contains(cfg.DisabledScanners, "process") {
		t.Errorf("process scanner should not be disabled when IncludeProcesses is true")
	}
	if !contains(cfg.DisabledScanners, "port") {
		t.Errorf("port scanner should still be disabled")
	}

	// Test IncludeDynamic override
	configContent = `
kernelParams:
  - fs.dentry-state
  - kernel.random.uuid
`
	if err := os.WriteFile(configPath, []byte(configContent), 0644); err != nil {
		t.Fatalf("Failed to create test config file: %v", err)
	}

	cfg, err = Load(configPath, CLIOptions{IncludeDynamic: true})
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}
	if contains(cfg.KernelParams, "fs.dentry-state") {
		t.Errorf("Dynamic kernel params should be excluded when IncludeDynamic is true")
	}
	if contains(cfg.KernelParams, "kernel.random.uuid") {
		t.Errorf("Dynamic kernel params should be excluded when IncludeDynamic is true")
	}
}

// Helper function to check if a slice contains a string
func contains(slice []string, item string) bool {
	for _, s := range slice {
		if s == item {
			return true
		}
	}
	return false
}
