package cmd

import (
	"testing"
)

func TestCleanupCommandExists(t *testing.T) {
	if cleanupCmd == nil {
		t.Fatal("cleanupCmd is nil")
	}

	if cleanupCmd.Use != "cleanup" {
		t.Errorf("Expected Use='cleanup', got %s", cleanupCmd.Use)
	}
}
