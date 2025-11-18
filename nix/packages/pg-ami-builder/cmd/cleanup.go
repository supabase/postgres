package cmd

import (
	"bufio"
	"context"
	"fmt"
	"os"
	"strings"

	"github.com/spf13/cobra"
	"github.com/supabase/postgres/pg-ami-builder/internal/aws"
	"github.com/supabase/postgres/pg-ami-builder/internal/state"
)

var (
	cleanupInstanceID string
	cleanupForce      bool
	cleanupPhase      string
)

var cleanupCmd = &cobra.Command{
	Use:   "cleanup",
	Short: "Terminate instance and remove associated resources",
	Long: `Terminate the EC2 instance and cleanup associated resources.

By default, uses the instance from the state file. Override with --instance-id or --phase.
Will prompt for confirmation unless --force is used.`,
	RunE: runCleanup,
}

func runCleanup(cmd *cobra.Command, args []string) error {
	ctx := context.Background()

	// Get instance ID and state
	instanceID := cleanupInstanceID
	var buildState *state.State
	stateFilePath := stateFile

	if instanceID == "" {
		if stateFilePath == "" {
			var err error
			stateFilePath, err = state.GetDefaultStateFile()
			if err != nil {
				return fmt.Errorf("failed to get default state file: %w", err)
			}
		}

		var err error
		buildState, err = state.LoadState(stateFilePath)
		if err != nil {
			return fmt.Errorf("failed to load state: %w", err)
		}

		region = buildState.Region

		// Get instance ID from phase-specific state
		if cleanupPhase != "" {
			phaseState := buildState.GetPhaseState(cleanupPhase)
			if phaseState == nil || phaseState.InstanceID == "" {
				return fmt.Errorf("no instance found for %s in state file", cleanupPhase)
			}
			instanceID = phaseState.InstanceID
		} else {
			// Try to find any instance (prefer phase2, then phase1, then legacy)
			if buildState.Phase2 != nil && buildState.Phase2.InstanceID != "" {
				instanceID = buildState.Phase2.InstanceID
				cleanupPhase = "phase2"
			} else if buildState.Phase1 != nil && buildState.Phase1.InstanceID != "" {
				instanceID = buildState.Phase1.InstanceID
				cleanupPhase = "phase1"
			} else if buildState.InstanceID != "" {
				instanceID = buildState.InstanceID
				cleanupPhase = buildState.Phase
			}
		}
	}

	if instanceID == "" {
		return fmt.Errorf("no instance ID available (use --instance-id or check state file)")
	}

	// Display instance information
	fmt.Printf("Instance to terminate: %s\n", instanceID)
	if cleanupPhase != "" {
		fmt.Printf("Phase: %s\n", cleanupPhase)
	}
	if buildState != nil {
		phaseState := buildState.GetPhaseState(cleanupPhase)
		if phaseState != nil && phaseState.ExecutionID != "" {
			fmt.Printf("Execution ID: %s\n", phaseState.ExecutionID)
		}
	}
	fmt.Println()

	// Confirm termination
	if !cleanupForce {
		fmt.Print("Terminate this instance? [y/N]: ")
		reader := bufio.NewReader(os.Stdin)
		response, err := reader.ReadString('\n')
		if err != nil {
			return fmt.Errorf("failed to read input: %w", err)
		}

		response = strings.ToLower(strings.TrimSpace(response))
		if response != "y" && response != "yes" {
			fmt.Println("Cleanup cancelled")
			return nil
		}
	}

	// Create EC2 client
	ec2Client, err := aws.NewEC2Client(ctx, region)
	if err != nil {
		return fmt.Errorf("failed to create EC2 client: %w", err)
	}

	// Terminate instance
	fmt.Println("✓ Terminating instance...")
	if err := ec2Client.TerminateInstance(ctx, instanceID); err != nil {
		return fmt.Errorf("failed to terminate instance: %w", err)
	}

	fmt.Println("✓ Instance terminated")

	// Clear state file
	if stateFilePath != "" {
		if err := state.ClearState(stateFilePath); err != nil {
			fmt.Printf("Warning: failed to clear state file: %v\n", err)
		} else {
			fmt.Println("✓ State file cleared")
		}
	}

	return nil
}

func init() {
	rootCmd.AddCommand(cleanupCmd)

	cleanupCmd.Flags().StringVar(&cleanupInstanceID, "instance-id", "", "Target specific instance (default: from state file)")
	cleanupCmd.Flags().StringVar(&cleanupPhase, "phase", "", "Clean up specific phase (phase1 or phase2)")
	cleanupCmd.Flags().BoolVar(&cleanupForce, "force", false, "Skip confirmation prompt")
	cleanupCmd.Flags().StringVar(&region, "region", "us-east-1", "AWS region")
}
