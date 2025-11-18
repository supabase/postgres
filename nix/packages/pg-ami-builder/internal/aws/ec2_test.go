package aws

import (
	"testing"
)

func TestGenerateExecutionID(t *testing.T) {
	execID := GenerateExecutionID("15")
	if execID == "" {
		t.Fatal("GenerateExecutionID returned empty string")
	}

	// Should contain timestamp and version
	if len(execID) < 10 {
		t.Errorf("Execution ID too short: %s", execID)
	}
}

func TestBuildInstanceTags(t *testing.T) {
	tags := BuildInstanceTags("exec-123", "phase1")

	expectedTags := map[string]string{
		"creator":           "pg-ami-builder",
		"packerExecutionId": "exec-123",
		"appType":           "postgres",
		"phase":             "phase1",
		"managedBy":         "pg-ami-builder",
	}

	if len(tags) != len(expectedTags) {
		t.Fatalf("Expected %d tags, got %d", len(expectedTags), len(tags))
	}

	for k, expectedV := range expectedTags {
		found := false
		for _, tag := range tags {
			if *tag.Key == k && *tag.Value == expectedV {
				found = true
				break
			}
		}
		if !found {
			t.Errorf("Missing or incorrect tag %s=%s", k, expectedV)
		}
	}
}
