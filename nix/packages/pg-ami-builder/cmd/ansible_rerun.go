package cmd

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/spf13/cobra"
	"github.com/supabase/postgres/pg-ami-builder/internal/ansible"
	"github.com/supabase/postgres/pg-ami-builder/internal/git"
	"github.com/supabase/postgres/pg-ami-builder/internal/state"
)

var (
	rerunInstanceID string
	skipTags        []string
	syncFiles       bool
	sshPublicKey    string
	rerunGitSHA     string
)

var ansibleRerunCmd = &cobra.Command{
	Use:   "ansible-rerun [phase1|phase2]",
	Short: "Re-run ansible playbook from current branch on existing instance",
	Long: `Re-run the ansible playbook from your current branch on an existing instance.

This is useful for iterating on ansible changes without relaunching the instance.`,
	Args:      cobra.ExactArgs(1),
	ValidArgs: []string{"phase1", "phase2"},
	RunE:      runAnsibleRerun,
}

func runAnsibleRerun(cmd *cobra.Command, args []string) error {
	phase := args[0]
	if phase != "phase1" && phase != "phase2" {
		return fmt.Errorf("phase must be 'phase1' or 'phase2'")
	}

	ctx := context.Background()

	// Get instance ID from state or flag
	instanceID := rerunInstanceID
	if instanceID == "" {
		stateFilePath := stateFile
		if stateFilePath == "" {
			var err error
			stateFilePath, err = state.GetDefaultStateFile()
			if err != nil {
				return fmt.Errorf("failed to get default state file: %w", err)
			}
		}

		buildState, err := state.LoadState(stateFilePath)
		if err != nil {
			return fmt.Errorf("failed to load state: %w", err)
		}

		// Get phase-specific state
		phaseState := buildState.GetPhaseState(phase)
		if phaseState == nil {
			return fmt.Errorf("no state found for %s. Run build first", phase)
		}

		instanceID = phaseState.InstanceID
		region = buildState.Region
		postgresVersion = buildState.PostgresVersion
		if rerunGitSHA == "" {
			rerunGitSHA = buildState.GitSHA
		}
	}

	if instanceID == "" {
		return fmt.Errorf("no instance ID available (use --instance-id or run build command first)")
	}

	// Get git SHA if still not set
	if rerunGitSHA == "" {
		var err error
		rerunGitSHA, err = git.GetCurrentSHA()
		if err != nil {
			fmt.Printf("⚠ Could not get git SHA: %v, using 'unknown'\n", err)
			rerunGitSHA = "unknown"
		}
	}

	fmt.Printf("✓ Found instance: %s (region: %s)\n", instanceID, region)
	fmt.Printf("✓ Git SHA: %s\n", rerunGitSHA)

	// Get instance availability zone and public IP for SSH
	describeCmd := exec.CommandContext(ctx, "aws", "ec2", "describe-instances",
		"--instance-ids", instanceID,
		"--region", region,
		"--query", "Reservations[0].Instances[0].[Placement.AvailabilityZone,PublicIpAddress]",
		"--output", "text")

	output, err := describeCmd.Output()
	if err != nil {
		return fmt.Errorf("failed to describe instance: %w", err)
	}

	parts := strings.Fields(string(output))
	if len(parts) < 2 {
		return fmt.Errorf("failed to get instance details")
	}

	availabilityZone := parts[0]
	publicIP := parts[1]

	fmt.Printf("✓ Instance AZ: %s, IP: %s\n", availabilityZone, publicIP)

	// Find SSH public key if not specified
	if sshPublicKey == "" {
		homeDir := os.Getenv("HOME")
		// Try common key types in order
		keyPaths := []string{
			filepath.Join(homeDir, ".ssh", "id_ed25519.pub"),
			filepath.Join(homeDir, ".ssh", "id_rsa.pub"),
			filepath.Join(homeDir, ".ssh", "id_ecdsa.pub"),
		}

		for _, keyPath := range keyPaths {
			if _, err := os.Stat(keyPath); err == nil {
				sshPublicKey = keyPath
				break
			}
		}

		if sshPublicKey == "" {
			return fmt.Errorf("no SSH public key found in ~/.ssh/ (tried id_ed25519.pub, id_rsa.pub, id_ecdsa.pub). Use --ssh-public-key to specify one")
		}
	}

	fmt.Printf("✓ Using SSH key: %s\n", sshPublicKey)

	// Send SSH public key to instance
	fmt.Printf("✓ Authorizing SSH key...\n")

	sendKeyCmd := exec.CommandContext(ctx, "aws", "ec2-instance-connect", "send-ssh-public-key",
		"--instance-id", instanceID,
		"--region", region,
		"--availability-zone", availabilityZone,
		"--instance-os-user", "ubuntu",
		"--ssh-public-key", "file://"+sshPublicKey)

	sendKeyCmd.Stderr = os.Stderr
	sendKeyCmd.Stdout = os.Stdout

	if err := sendKeyCmd.Run(); err != nil {
		return fmt.Errorf("failed to send SSH public key: %w", err)
	}

	fmt.Printf("✓ SSH key authorized for 60 seconds\n")

	// Optionally sync files using rsync over regular SSH
	if syncFiles {
		fmt.Printf("✓ Syncing files to instance...\n")

		fileMappings := ansible.BuildFileList(phase)

		for _, mapping := range fileMappings {
			fmt.Printf("  - Syncing %s -> %s\n", mapping.Src, mapping.Dst)

			// Use rsync over regular SSH (key is already authorized)
			rsyncCmd := exec.CommandContext(ctx, "rsync", "-avz",
				"-e", "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null",
				mapping.Src,
				fmt.Sprintf("ubuntu@%s:%s", publicIP, mapping.Dst))

			rsyncCmd.Stdout = os.Stdout
			rsyncCmd.Stderr = os.Stderr

			if err := rsyncCmd.Run(); err != nil {
				return fmt.Errorf("failed to sync %s: %w", mapping.Src, err)
			}
		}

		fmt.Printf("✓ Files synced successfully\n")
	} else {
		fmt.Printf("✓ Using existing files on instance\n")
	}

	// Re-execute ansible via regular SSH
	var additionalArgs []string
	if len(skipTags) > 0 {
		skipTagsStr := strings.Join(skipTags, ",")
		additionalArgs = append(additionalArgs, "--skip-tags", skipTagsStr)
	}
	additionalArgs = append(additionalArgs, ansibleArgs...)

	executeCmd := ansible.BuildAnsiblePlaybookCommand(phase, postgresVersion, rerunGitSHA, additionalArgs)

	fmt.Printf("\n✓ Re-running %s ansible...\n", phase)
	fmt.Printf("✓ Executing: %s\n\n", executeCmd)

	// Execute command via regular SSH (key is already authorized)
	sshCmd := exec.CommandContext(ctx, "ssh",
		"-o", "StrictHostKeyChecking=no",
		"-o", "UserKnownHostsFile=/dev/null",
		fmt.Sprintf("ubuntu@%s", publicIP),
		executeCmd)

	sshCmd.Stdin = os.Stdin
	sshCmd.Stdout = os.Stdout
	sshCmd.Stderr = os.Stderr

	if err := sshCmd.Run(); err != nil {
		fmt.Printf("\n✗ Ansible execution failed\n")
		fmt.Printf("\nInstance still running. Debug with:\n")
		fmt.Printf("  - SSH: pg-ami-builder ssh\n")
		fmt.Printf("  - Cleanup: pg-ami-builder cleanup\n")
		return fmt.Errorf("ansible execution failed: %w", err)
	}

	fmt.Printf("\n✓ Ansible %s completed successfully\n", phase)
	fmt.Printf("\nNext steps:\n")
	fmt.Printf("  - Test changes: pg-ami-builder ssh\n")
	fmt.Printf("  - Cleanup when done: pg-ami-builder cleanup\n")

	return nil
}

func init() {
	rootCmd.AddCommand(ansibleRerunCmd)

	ansibleRerunCmd.Flags().StringVar(&rerunInstanceID, "instance-id", "", "Target specific instance (default: from state file)")
	ansibleRerunCmd.Flags().StringSliceVar(&ansibleArgs, "ansible-args", []string{}, "Additional ansible arguments")
	ansibleRerunCmd.Flags().StringSliceVar(&skipTags, "skip-tags", []string{}, "Ansible tags to skip")
	ansibleRerunCmd.Flags().StringVar(&region, "region", "us-east-1", "AWS region")
	ansibleRerunCmd.Flags().BoolVar(&syncFiles, "sync-files", false, "Sync local files to instance before re-running ansible")
	ansibleRerunCmd.Flags().StringVar(&sshPublicKey, "ssh-public-key", "", "SSH public key path (default: auto-detect from ~/.ssh/)")
	ansibleRerunCmd.Flags().StringVar(&rerunGitSHA, "git-sha", "", "Git SHA for nix packages (default: from state file or current HEAD)")
}
