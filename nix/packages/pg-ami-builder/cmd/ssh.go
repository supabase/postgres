package cmd

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"

	"github.com/spf13/cobra"
	"github.com/supabase/postgres/pg-ami-builder/internal/state"
)

var (
	sshInstanceID    string
	sshPhase         string
	awsEC2ConnectCmd string
)

var sshCmd = &cobra.Command{
	Use:   "ssh",
	Short: "Connect to instance via EC2 Instance Connect",
	Long: `Connect to the instance using AWS EC2 Instance Connect.

By default, uses the instance ID from the state file. Override with --instance-id.
Use --aws-ec2-connect-cmd to provide a full custom AWS EC2 Instance Connect command string.`,
	RunE: runSSH,
}

func runSSH(cmd *cobra.Command, args []string) error {
	ctx := context.Background()

	// Use EC2 Instance Connect if AWS CLI command is provided
	if awsEC2ConnectCmd != "" {
		return connectViaEC2InstanceConnect(ctx)
	}

	// Get instance ID from state or flag
	instanceID := sshInstanceID
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

		region = buildState.Region

		// Get instance ID from phase-specific state
		if sshPhase != "" {
			phaseState := buildState.GetPhaseState(sshPhase)
			if phaseState == nil || phaseState.InstanceID == "" {
				return fmt.Errorf("no instance found for %s in state file", sshPhase)
			}
			instanceID = phaseState.InstanceID
		} else {
			// Auto-detect: prefer phase2, then phase1, then legacy
			if buildState.Phase2 != nil && buildState.Phase2.InstanceID != "" {
				instanceID = buildState.Phase2.InstanceID
				fmt.Println("✓ Auto-detected phase2 instance")
			} else if buildState.Phase1 != nil && buildState.Phase1.InstanceID != "" {
				instanceID = buildState.Phase1.InstanceID
				fmt.Println("✓ Auto-detected phase1 instance")
			} else if buildState.InstanceID != "" {
				instanceID = buildState.InstanceID
			}
		}
	}

	if instanceID == "" {
		return fmt.Errorf("no instance ID available (use --instance-id or --phase, or run build command first)")
	}

	// Connect via EC2 Instance Connect
	return connectViaEC2InstanceConnectDirect(ctx, instanceID, region)
}

func connectViaEC2InstanceConnect(ctx context.Context) error {
	fmt.Printf("✓ Connecting via EC2 Instance Connect...\n")

	// Create temporary SSH config file
	tempSSHConfig, err := os.CreateTemp("", "ssh-config-*")
	if err != nil {
		return fmt.Errorf("failed to create temp SSH config: %w", err)
	}
	defer os.Remove(tempSSHConfig.Name())

	// Write SSH config with StrictHostKeyChecking disabled
	sshConfig := `Host *
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    LogLevel ERROR
`
	if _, err := tempSSHConfig.WriteString(sshConfig); err != nil {
		return fmt.Errorf("failed to write SSH config: %w", err)
	}
	tempSSHConfig.Close()

	// Create temporary directory for SSH wrapper
	tempBinDir, err := os.MkdirTemp("", "ssh-wrapper-*")
	if err != nil {
		return fmt.Errorf("failed to create temp bin directory: %w", err)
	}
	defer os.RemoveAll(tempBinDir)

	// Create SSH wrapper script
	wrapperPath := filepath.Join(tempBinDir, "ssh")
	wrapperContent := fmt.Sprintf("#!/bin/bash\nexec /usr/bin/ssh -F \"%s\" \"$@\"\n", tempSSHConfig.Name())

	if err := os.WriteFile(wrapperPath, []byte(wrapperContent), 0o755); err != nil {
		return fmt.Errorf("failed to create SSH wrapper: %w", err)
	}

	fmt.Printf("✓ Created temporary SSH wrapper\n")

	// Prepend temp bin directory to PATH
	originalPath := os.Getenv("PATH")
	os.Setenv("PATH", fmt.Sprintf("%s:%s", tempBinDir, originalPath))
	defer os.Setenv("PATH", originalPath)

	// Execute the AWS CLI command
	fmt.Printf("✓ Executing: %s\n\n", awsEC2ConnectCmd)

	cmd := exec.CommandContext(ctx, "bash", "-c", awsEC2ConnectCmd)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	if err := cmd.Run(); err != nil {
		return fmt.Errorf("AWS EC2 Instance Connect command failed: %w", err)
	}

	return nil
}

func connectViaEC2InstanceConnectDirect(ctx context.Context, instanceID, region string) error {
	fmt.Printf("✓ Connecting via EC2 Instance Connect...\n")
	fmt.Printf("  Instance: %s\n", instanceID)
	fmt.Printf("  Region: %s\n\n", region)

	// Build the AWS CLI command
	awsCmd := exec.CommandContext(ctx, "aws", "ec2-instance-connect", "ssh",
		"--instance-id", instanceID,
		"--region", region,
		"--os-user", "ubuntu")

	awsCmd.Stdin = os.Stdin
	awsCmd.Stdout = os.Stdout
	awsCmd.Stderr = os.Stderr

	if err := awsCmd.Run(); err != nil {
		return fmt.Errorf("EC2 Instance Connect failed: %w", err)
	}

	return nil
}

func init() {
	rootCmd.AddCommand(sshCmd)

	sshCmd.Flags().StringVar(&sshInstanceID, "instance-id", "", "Target specific instance (default: from state file)")
	sshCmd.Flags().StringVar(&sshPhase, "phase", "", "Connect to specific phase instance (phase1 or phase2)")
	sshCmd.Flags().StringVar(&region, "region", "us-east-1", "AWS region")
	sshCmd.Flags().StringVar(&awsEC2ConnectCmd, "aws-ec2-connect-cmd", "", "Custom AWS EC2 Instance Connect command (e.g., 'aws ec2-instance-connect ssh --instance-id i-xxx ...')")
}
