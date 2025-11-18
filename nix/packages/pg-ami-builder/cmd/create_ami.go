package cmd

import (
	"context"
	"fmt"
	"time"

	"github.com/spf13/cobra"
	"github.com/supabase/postgres/pg-ami-builder/internal/aws"
	"github.com/supabase/postgres/pg-ami-builder/internal/state"
)

var createAMICmd = &cobra.Command{
	Use:       "create-ami [phase1|phase2]",
	Short:     "Create AMI from instance",
	Long:      `Create an AMI from the instance used during ansible-rerun for the specified phase.`,
	Args:      cobra.ExactArgs(1),
	ValidArgs: []string{"phase1", "phase2"},
	RunE:      runCreateAMI,
}

func runCreateAMI(cmd *cobra.Command, args []string) error {
	phase := args[0]
	if phase != "phase1" && phase != "phase2" {
		return fmt.Errorf("phase must be 'phase1' or 'phase2'")
	}

	ctx := context.Background()

	// Load state
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
	if phaseState == nil || phaseState.InstanceID == "" {
		return fmt.Errorf("no instance ID found for %s. Run ansible-rerun first", phase)
	}

	instanceID := phaseState.InstanceID
	executionID := phaseState.ExecutionID

	fmt.Printf("✓ Found %s instance: %s\n", phase, instanceID)
	fmt.Printf("✓ Execution ID: %s\n", executionID)

	// Create EC2 client
	ec2Client, err := aws.NewEC2Client(ctx, buildState.Region)
	if err != nil {
		return fmt.Errorf("failed to create EC2 client: %w", err)
	}

	// Generate AMI name
	timestamp := time.Now().Unix()
	var amiName string
	if phase == "phase1" {
		amiName = fmt.Sprintf("supabase-postgres-%s-stage-1-%d", buildState.PostgresVersion, timestamp)
	} else {
		amiName = fmt.Sprintf("supabase-postgres-%s-%d", buildState.PostgresVersion, timestamp)
	}

	fmt.Printf("✓ Creating AMI: %s\n", amiName)

	// Create the AMI
	amiInput := &aws.CreateAMIInput{
		InstanceID:      instanceID,
		ExecutionID:     executionID,
		Phase:           phase,
		PostgresVersion: buildState.PostgresVersion,
		GitSHA:          buildState.GitSHA,
	}

	amiID, err := ec2Client.CreateAMI(ctx, amiInput)
	if err != nil {
		return fmt.Errorf("failed to create AMI: %w", err)
	}

	fmt.Printf("✓ AMI created: %s\n", amiID)
	fmt.Printf("✓ Waiting for AMI to be available...\n")

	// Wait for AMI to be available
	if err := ec2Client.WaitForAMIAvailable(ctx, amiID); err != nil {
		return fmt.Errorf("failed waiting for AMI: %w", err)
	}

	fmt.Printf("✓ AMI is now available\n")

	// Update state with AMI ID
	phaseState.AMIID = amiID
	phaseState.Timestamp = time.Now().Format(time.RFC3339)
	buildState.SetPhaseState(phase, phaseState)

	if err := state.SaveState(stateFilePath, buildState); err != nil {
		return fmt.Errorf("failed to save state: %w", err)
	}

	fmt.Printf("✓ State updated: %s\n", stateFilePath)

	if phase == "phase1" {
		fmt.Printf("\nNext: Run phase 2 with:\n")
		fmt.Printf("  pg-ami-builder build phase2 --postgres-version %s\n", buildState.PostgresVersion)
	} else {
		fmt.Printf("\n✓ Final production AMI ready: %s\n", amiID)
	}

	return nil
}

func init() {
	rootCmd.AddCommand(createAMICmd)
	createAMICmd.Flags().StringVar(&stateFile, "state-file", "", "Custom state file path")
}
