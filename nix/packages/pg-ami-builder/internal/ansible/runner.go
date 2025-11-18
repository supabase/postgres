package ansible

import (
	"fmt"
	"strings"
)

// FileMapping represents a source to destination file mapping
type FileMapping struct {
	Src string
	Dst string
}

// BuildFileList returns the list of files to sync based on phase
func BuildFileList(phase string) []FileMapping {
	// Base files synced for both phases (matching packer templates)
	baseMappings := []FileMapping{
		{Src: "ansible/", Dst: "/tmp/ansible-playbook/ansible/"},
		{Src: "scripts/", Dst: "/tmp/ansible-playbook/scripts/"},
		{Src: "ansible/vars.yml", Dst: "/tmp/ansible-playbook/vars.yml"},
	}

	if phase == "phase2" {
		baseMappings = append(baseMappings, FileMapping{
			Src: "migrations/",
			Dst: "/tmp/migrations/",
		})
	}

	return baseMappings
}

// BuildAnsiblePlaybookCommand constructs the full ansible-playbook command for re-running
func BuildAnsiblePlaybookCommand(phase, postgresVersion, gitSHA string, additionalArgs []string) string {
	var cmd string

	if phase == "phase1" {
		// Phase1: Run ansible-playbook locally (not in chroot like packer does)
		cmd = fmt.Sprintf(
			"ansible-playbook -c local -i 'localhost,' /tmp/ansible-playbook/ansible/playbook.yml "+
				"--extra-vars '{\"nixpkg_mode\": true, \"debpkg_mode\": false, \"stage2_nix\": false}' "+
				"--extra-vars \"psql_version=psql_%s\" "+
				"-e postgresql_major=%s",
			postgresVersion, postgresVersion)
	} else {
		// Phase2: Run the nix provision script with required env vars
		cmd = fmt.Sprintf(
			"export GIT_SHA=%s && export POSTGRES_MAJOR_VERSION=%s && bash /tmp/ansible-playbook/scripts/nix-provision.sh",
			gitSHA, postgresVersion)
	}

	// Add any additional arguments
	if len(additionalArgs) > 0 {
		cmd = cmd + " " + strings.Join(additionalArgs, " ")
	}

	return cmd
}
