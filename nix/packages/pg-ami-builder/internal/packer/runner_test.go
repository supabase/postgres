package packer

import (
	"strings"
	"testing"
)

func TestBuildPackerCommand(t *testing.T) {
	tests := []struct {
		name             string
		phase            string
		postgresVersion  string
		executionID      string
		expectedContains []string
	}{
		{
			name:            "phase1 build",
			phase:           "phase1",
			postgresVersion: "15",
			executionID:     "1234567890-15",
			expectedContains: []string{
				"packer",
				"build",
				"amazon-arm64-nix.pkr.hcl",
				"-var", "postgres-version=15",
				"-var", "packer-execution-id=1234567890-15",
			},
		},
		{
			name:            "phase2 build",
			phase:           "phase2",
			postgresVersion: "16",
			executionID:     "1234567890-16",
			expectedContains: []string{
				"packer",
				"build",
				"stage2-nix-psql.pkr.hcl",
				"-var", "postgres-version=16",
				"-var", "packer-execution-id=1234567890-16",
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			cmd := BuildPackerCommand(tt.phase, tt.postgresVersion, tt.executionID, map[string]string{})
			cmdStr := strings.Join(cmd, " ")

			for _, expected := range tt.expectedContains {
				if !strings.Contains(cmdStr, expected) {
					t.Errorf("BuildPackerCommand missing %q in: %s", expected, cmdStr)
				}
			}
		})
	}
}

func TestGetPackerTemplate(t *testing.T) {
	tests := []struct {
		phase    string
		expected string
	}{
		{"phase1", "amazon-arm64-nix.pkr.hcl"},
		{"phase2", "stage2-nix-psql.pkr.hcl"},
	}

	for _, tt := range tests {
		t.Run(tt.phase, func(t *testing.T) {
			result := GetPackerTemplate(tt.phase)
			if result != tt.expected {
				t.Errorf("GetPackerTemplate(%q) = %q, want %q", tt.phase, result, tt.expected)
			}
		})
	}
}
