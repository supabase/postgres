package cmd

import (
	"testing"
)

func TestSSHCommandExists(t *testing.T) {
	if sshCmd == nil {
		t.Fatal("sshCmd is nil")
	}

	if sshCmd.Use != "ssh" {
		t.Errorf("Expected Use='ssh', got %s", sshCmd.Use)
	}
}
