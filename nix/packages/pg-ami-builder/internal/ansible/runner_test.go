package ansible

import (
	"strings"
	"testing"
)

func TestBuildFileList(t *testing.T) {
	tests := []struct {
		name  string
		phase string
		want  []FileMapping
	}{
		{
			name:  "phase1",
			phase: "phase1",
			want: []FileMapping{
				{Src: "ansible/", Dst: "/tmp/ansible-playbook/ansible/"},
				{Src: "scripts/", Dst: "/tmp/ansible-playbook/scripts/"},
				{Src: "ansible/vars.yml", Dst: "/tmp/ansible-playbook/vars.yml"},
			},
		},
		{
			name:  "phase2",
			phase: "phase2",
			want: []FileMapping{
				{Src: "ansible/", Dst: "/tmp/ansible-playbook/ansible/"},
				{Src: "scripts/", Dst: "/tmp/ansible-playbook/scripts/"},
				{Src: "ansible/vars.yml", Dst: "/tmp/ansible-playbook/vars.yml"},
				{Src: "migrations/", Dst: "/tmp/migrations/"},
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := BuildFileList(tt.phase)
			if len(got) != len(tt.want) {
				t.Errorf("BuildFileList() returned %d mappings, want %d", len(got), len(tt.want))
			}
		})
	}
}

func TestBuildAnsiblePlaybookCommand(t *testing.T) {
	tests := []struct {
		name           string
		phase          string
		postgresVer    string
		gitSHA         string
		additionalArgs []string
		wantContains   []string
	}{
		{
			name:           "phase1 basic",
			phase:          "phase1",
			postgresVer:    "17",
			gitSHA:         "abc123",
			additionalArgs: []string{},
			wantContains:   []string{"ansible-playbook", "localhost", "postgresql_major=17", "psql_17"},
		},
		{
			name:           "phase1 with skip tags",
			phase:          "phase1",
			postgresVer:    "16",
			gitSHA:         "def456",
			additionalArgs: []string{"--skip-tags", "migrations"},
			wantContains:   []string{"ansible-playbook", "postgresql_major=16", "--skip-tags", "migrations"},
		},
		{
			name:           "phase2 basic",
			phase:          "phase2",
			postgresVer:    "15",
			gitSHA:         "xyz789",
			additionalArgs: []string{},
			wantContains:   []string{"nix-provision.sh", "GIT_SHA=xyz789", "POSTGRES_MAJOR_VERSION=15"},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := BuildAnsiblePlaybookCommand(tt.phase, tt.postgresVer, tt.gitSHA, tt.additionalArgs)
			for _, want := range tt.wantContains {
				if !strings.Contains(got, want) {
					t.Errorf("BuildAnsiblePlaybookCommand() = %s, want to contain %s", got, want)
				}
			}
		})
	}
}
