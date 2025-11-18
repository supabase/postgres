package cmd

import (
	"strings"
	"testing"
)

func TestAnsibleRerunCommandExists(t *testing.T) {
	if ansibleRerunCmd == nil {
		t.Fatal("ansibleRerunCmd is nil")
	}

	if !strings.HasPrefix(ansibleRerunCmd.Use, "ansible-rerun") {
		t.Errorf("Expected Use to start with 'ansible-rerun', got %s", ansibleRerunCmd.Use)
	}
}

func TestAnsibleRerunRequiresPhase(t *testing.T) {
	// Test that ValidateArgs requires exactly 1 argument
	err := ansibleRerunCmd.Args(ansibleRerunCmd, []string{})
	if err == nil {
		t.Error("Expected error for missing phase argument")
	}

	// Test with valid phase
	err = ansibleRerunCmd.Args(ansibleRerunCmd, []string{"phase1"})
	if err != nil {
		t.Errorf("Expected no error for valid phase, got: %v", err)
	}
}
