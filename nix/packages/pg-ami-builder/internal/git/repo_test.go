package git

import (
	"testing"
)

func TestGetCurrentSHA(t *testing.T) {
	sha, err := GetCurrentSHA()
	if err != nil {
		t.Skipf("Not in a git repository: %v", err)
	}

	if len(sha) != 40 {
		t.Errorf("Expected 40 character SHA, got %d: %s", len(sha), sha)
	}
}

func TestGetCurrentBranch(t *testing.T) {
	branch, err := GetCurrentBranch()
	if err != nil {
		t.Skipf("Not in a git repository: %v", err)
	}

	if branch == "" {
		t.Error("Expected non-empty branch name")
	}
}
