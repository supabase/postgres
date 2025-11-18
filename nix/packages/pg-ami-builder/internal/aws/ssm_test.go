package aws

import (
	"strings"
	"testing"
)

func TestBuildSSMCommand(t *testing.T) {
	tests := []struct {
		name    string
		script  string
		wantCmd bool
	}{
		{
			name:    "simple script",
			script:  "echo hello",
			wantCmd: true,
		},
		{
			name:    "multiline script",
			script:  "#!/bin/bash\necho hello\necho world",
			wantCmd: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			cmd := BuildSSMCommand(tt.script)
			if (cmd != "") != tt.wantCmd {
				t.Errorf("BuildSSMCommand() = %v, wantCmd %v", cmd != "", tt.wantCmd)
			}
		})
	}
}

func TestBuildTarCommand(t *testing.T) {
	tests := []struct {
		name     string
		src      string
		expected string
	}{
		{
			name:     "directory sync",
			src:      "ansible/",
			expected: "mkdir -p ansible && tar -czf - ansible/ | base64",
		},
		{
			name:     "file sync",
			src:      "ansible/vars.yml",
			expected: "mkdir -p ansible && tar -czf - ansible/vars.yml | base64",
		},
		{
			name:     "top level file",
			src:      "README.md",
			expected: "tar -czf - README.md | base64",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := BuildTarCommand(tt.src)
			if result != tt.expected {
				t.Errorf("BuildTarCommand(%q) = %q, want %q", tt.src, result, tt.expected)
			}
		})
	}
}

func TestBuildUntarCommand(t *testing.T) {
	dst := "/tmp/ansible-playbook/ansible/"
	expected := "mkdir -p /tmp/ansible-playbook/ansible/ && base64 -d | tar -xzf - -C /tmp/ansible-playbook/ansible/"

	result := BuildUntarCommand(dst)
	if result != expected {
		t.Errorf("BuildUntarCommand(%q) = %q, want %q", dst, result, expected)
	}
}

func TestSyncFileCommand(t *testing.T) {
	dst := "/tmp/ansible-playbook/ansible/"
	tarData := "base64encodeddata"

	result := BuildSyncFileCommand(dst, tarData)
	if !strings.Contains(result, "base64 -d") {
		t.Errorf("BuildSyncFileCommand should contain base64 decode")
	}
	if !strings.Contains(result, "tar -xzf") {
		t.Errorf("BuildSyncFileCommand should contain tar extract")
	}
	if !strings.Contains(result, tarData) {
		t.Errorf("BuildSyncFileCommand should contain the tar data")
	}
}
