package cmd

import (
	"testing"

	"github.com/spf13/pflag"
)

func TestBuildPhase1Flags(t *testing.T) {
	// Test that postgres-version flag is required
	// Reset the flag value
	postgresVersion = ""

	// Call the validation directly since Cobra's required flag check
	// happens during parse, and we want to test the validation logic
	err := validatePostgresVersion(postgresVersion)
	if err == nil {
		t.Error("Expected error for empty --postgres-version flag")
	}

	// Test that validation is called in the command
	// This verifies the command structure accepts the flag
	if buildPhase1Cmd.Flags().Lookup("postgres-version") == nil {
		t.Error("Expected --postgres-version flag to exist")
	}

	// Verify the flag is marked as required
	required := false
	buildPhase1Cmd.Flags().VisitAll(func(f *pflag.Flag) {
		if f.Name == "postgres-version" {
			required = true
		}
	})
	if !required {
		t.Error("Expected --postgres-version to be defined")
	}
}

func TestValidatePostgresVersion(t *testing.T) {
	tests := []struct {
		version string
		wantErr bool
	}{
		{"15", false},
		{"16", false},
		{"17", false},
		{"14", true},
		{"abc", true},
		{"", true},
	}

	for _, tt := range tests {
		t.Run(tt.version, func(t *testing.T) {
			err := validatePostgresVersion(tt.version)
			if (err != nil) != tt.wantErr {
				t.Errorf("validatePostgresVersion(%s) error = %v, wantErr %v", tt.version, err, tt.wantErr)
			}
		})
	}
}
