package cmd

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/spf13/cobra"
	"github.com/supabase/postgres/pg-ami-builder/internal/aws"
	"github.com/supabase/postgres/pg-ami-builder/internal/git"
	"github.com/supabase/postgres/pg-ami-builder/internal/packer"
	"github.com/supabase/postgres/pg-ami-builder/internal/state"
)

var (
	postgresVersion string
	region          string
	createAMI       bool
	ansibleArgs     []string
	instanceType    string
	stateFile       string
	sourceAMI       string
	gitSHA          string
)

var buildCmd = &cobra.Command{
	Use:   "build",
	Short: "Build AMI phases",
	Long:  `Build phase1 or phase2 of the AMI`,
}

var buildPhase1Cmd = &cobra.Command{
	Use:   "phase1",
	Short: "Launch instance and run phase 1 ansible",
	RunE:  runBuildPhase1,
}

var buildPhase2Cmd = &cobra.Command{
	Use:   "phase2",
	Short: "Launch instance from stage-1 AMI and run phase 2 ansible",
	RunE:  runBuildPhase2,
}

func validatePostgresVersion(version string) error {
	validVersions := map[string]bool{
		"15": true,
		"16": true,
		"17": true,
	}

	if !validVersions[version] {
		return fmt.Errorf("invalid postgres version: %s (must be 15, 16, or 17)", version)
	}
	return nil
}

func runBuildPhase1(cmd *cobra.Command, args []string) error {
	if err := validatePostgresVersion(postgresVersion); err != nil {
		return err
	}

	ctx := context.Background()

	// Get git information
	sha, err := git.GetCurrentSHA()
	if err != nil {
		return fmt.Errorf("failed to get git SHA: %w", err)
	}

	// Generate execution ID
	executionID := aws.GenerateExecutionID(postgresVersion)

	fmt.Printf("✓ Execution ID: %s\n", executionID)
	fmt.Printf("✓ Git SHA: %s\n", sha)

	// Get repo root for packer execution
	repoRoot, err := git.GetRepoRoot()
	if err != nil {
		return fmt.Errorf("failed to get repo root: %w", err)
	}

	// Rewrite template with unique AMI name
	templatePath := filepath.Join(repoRoot, packer.GetPackerTemplate("phase1"))
	tempTemplate, cleanup, err := packer.RewriteTemplateWithUniqueAMI(templatePath, executionID, "")
	if err != nil {
		return fmt.Errorf("failed to rewrite template: %w", err)
	}
	defer cleanup()

	// Build packer command with temp template
	// Match CI behavior: pass postgresql_major to ansible instead of skipping tags
	packerVars := map[string]string{
		"region":            region,
		"git-head-version":  sha,
		"ansible_arguments": fmt.Sprintf("-e postgresql_major=%s", postgresVersion),
	}
	packerCmd := packer.BuildPackerCommand("phase1", postgresVersion, executionID, packerVars)

	// Replace template path with temp template
	packerCmd[len(packerCmd)-1] = tempTemplate

	fmt.Printf("\n✓ Running packer build with unique AMI name...\n")
	fmt.Printf("  Command: %s\n\n", strings.Join(packerCmd, " "))

	// Execute packer build
	packerExec := exec.CommandContext(ctx, packerCmd[0], packerCmd[1:]...)
	packerExec.Dir = repoRoot // Run from repo root
	packerExec.Stdout = os.Stdout
	packerExec.Stderr = os.Stderr

	packerErr := packerExec.Run()

	// Initialize EC2 client for instance discovery if packer failed
	if packerErr != nil {
		fmt.Printf("\n✗ Packer build failed: %v\n", packerErr)

		// Get state file path first
		stateFilePath := stateFile
		if stateFilePath == "" {
			var err error
			stateFilePath, err = state.GetDefaultStateFile()
			if err != nil {
				fmt.Printf("⚠ Could not get state file path: %v\n", err)
				return fmt.Errorf("packer build failed: %w", packerErr)
			}
		}

		// Load existing state or create new
		buildState, err := state.LoadState(stateFilePath)
		if err != nil {
			// Create new state if none exists
			buildState = &state.State{
				Region:          region,
				PostgresVersion: postgresVersion,
				GitSHA:          sha,
			}
		}

		// Try to find the packer instance by tag
		var instanceID string
		ec2Client, err := aws.NewEC2Client(ctx, region)
		if err != nil {
			fmt.Printf("⚠ Could not create EC2 client to find instance: %v\n", err)
		} else {
			fmt.Println("\n✓ Looking for packer instance...")
			instanceID, err = ec2Client.FindInstanceByTag(ctx, "packerExecutionId", executionID)
			if err != nil {
				fmt.Printf("⚠ Could not find packer instance: %v\n", err)
				fmt.Println("  Packer may have cleaned up the instance already.")
			} else {
				fmt.Printf("✓ Found packer instance: %s\n", instanceID)
			}
		}

		// Save state with execution ID (and instance ID if found)
		buildState.SetPhaseState("phase1", &state.PhaseState{
			InstanceID:  instanceID, // Will be empty string if not found
			ExecutionID: executionID,
			Timestamp:   time.Now().Format(time.RFC3339),
		})

		if err := state.SaveState(stateFilePath, buildState); err != nil {
			fmt.Printf("⚠ Could not save state: %v\n", err)
		} else {
			fmt.Printf("\n✓ State saved to: %s\n", stateFilePath)
			fmt.Printf("  Execution ID: %s\n", executionID)
			if instanceID != "" {
				fmt.Printf("  Instance ID: %s\n", instanceID)
				fmt.Printf("\nNext steps:\n")
				fmt.Printf("  - SSH into instance: pg-ami-builder ssh\n")
				fmt.Printf("  - Re-run ansible: pg-ami-builder ansible-rerun phase1 --sync-files\n")
				fmt.Printf("  - Cleanup: pg-ami-builder cleanup\n")
			} else {
				fmt.Printf("\nNo instance available for debugging (already cleaned up by packer)\n")
			}
		}

		return fmt.Errorf("packer build failed: %w", packerErr)
	}

	fmt.Printf("\n✓ Packer build completed successfully!\n")
	fmt.Println("✓ AMI created by packer")

	// Find AMI by execution ID tag (injected by our template rewriter)
	var amiID string
	ec2Client, err := aws.NewEC2Client(ctx, region)
	if err != nil {
		fmt.Printf("⚠ Could not create EC2 client to find AMI: %v\n", err)
	} else {
		amiID, err = ec2Client.FindAMIByTag(ctx, "packerExecutionId", executionID)
		if err != nil {
			fmt.Printf("⚠ Could not find created AMI: %v\n", err)
		} else {
			fmt.Printf("✓ AMI ID: %s\n", amiID)
		}
	}

	// Save state even if we couldn't find the AMI
	stateFilePath := stateFile
	if stateFilePath == "" {
		stateFilePath, err = state.GetDefaultStateFile()
		if err != nil {
			fmt.Printf("⚠ Could not get state file path: %v\n", err)
			fmt.Println("\n✓ Build phase 1 complete!")
			return nil
		}
	}

	// Load existing state or create new
	buildState, err := state.LoadState(stateFilePath)
	if err != nil {
		buildState = &state.State{
			Region:          region,
			PostgresVersion: postgresVersion,
			GitSHA:          sha,
		}
	}

	buildState.SetPhaseState("phase1", &state.PhaseState{
		ExecutionID: executionID,
		AMIID:       amiID, // Will be empty if not found
		Timestamp:   time.Now().Format(time.RFC3339),
	})

	if err := state.SaveState(stateFilePath, buildState); err != nil {
		fmt.Printf("⚠ Could not save state: %v\n", err)
	} else {
		fmt.Printf("✓ State saved to: %s\n", stateFilePath)
	}

	fmt.Println("\n✓ Build phase 1 complete!")
	if amiID != "" {
		fmt.Printf("\nNext: Run phase 2 with:\n")
		fmt.Printf("  pg-ami-builder build phase2 --postgres-version %s\n", postgresVersion)
	} else {
		fmt.Printf("\nNote: AMI ID not automatically detected. You can manually add it to:\n")
		fmt.Printf("  %s\n", stateFilePath)
	}
	return nil
}

func runBuildPhase2(cmd *cobra.Command, args []string) error {
	if err := validatePostgresVersion(postgresVersion); err != nil {
		return err
	}

	ctx := context.Background()

	// If --source-ami not provided, read from state
	if sourceAMI == "" {
		stateFilePath := stateFile
		if stateFilePath == "" {
			var err error
			stateFilePath, err = state.GetDefaultStateFile()
			if err != nil {
				return fmt.Errorf("failed to get state file path: %w", err)
			}
		}

		buildState, err := state.LoadState(stateFilePath)
		if err != nil {
			return fmt.Errorf("no --source-ami provided and failed to load from state: %w\nRun phase1 first or provide --source-ami", err)
		}

		// Get phase1 AMI
		phase1State := buildState.GetPhaseState("phase1")
		if phase1State == nil || phase1State.AMIID == "" {
			return fmt.Errorf("no AMI ID found in state file. Run phase1 first or provide --source-ami")
		}

		sourceAMI = phase1State.AMIID
		fmt.Printf("✓ Using AMI from phase1 state: %s\n", sourceAMI)
	}

	// Get git SHA
	sha := gitSHA
	if sha == "" {
		var err error
		sha, err = git.GetCurrentSHA()
		if err != nil {
			return fmt.Errorf("failed to get git SHA: %w", err)
		}
	}

	// Generate execution ID
	executionID := aws.GenerateExecutionID(postgresVersion)

	fmt.Printf("✓ Phase 2 Build\n")
	fmt.Printf("✓ Source AMI: %s\n", sourceAMI)
	fmt.Printf("✓ Postgres Version: %s\n", postgresVersion)
	fmt.Printf("✓ Execution ID: %s\n", executionID)
	fmt.Printf("✓ Git SHA: %s\n", sha)

	// Get repo root for packer execution
	repoRoot, err := git.GetRepoRoot()
	if err != nil {
		return fmt.Errorf("failed to get repo root: %w", err)
	}

	// Rewrite template with unique AMI name
	templatePath := filepath.Join(repoRoot, packer.GetPackerTemplate("phase2"))
	tempTemplate, cleanup, err := packer.RewriteTemplateWithUniqueAMI(templatePath, executionID, "")
	if err != nil {
		return fmt.Errorf("failed to rewrite template: %w", err)
	}
	defer cleanup()

	// Build packer command with temp template
	packerVars := map[string]string{
		"region":                 region,
		"git-head-version":       sha,
		"source-ami":             sourceAMI, // Pass source AMI as variable
		"git_sha":                sha,
		"postgres_major_version": postgresVersion, // Needed by ansible scripts
	}
	packerCmd := packer.BuildPackerCommand("phase2", postgresVersion, executionID, packerVars)

	// Replace template path with temp template
	packerCmd[len(packerCmd)-1] = tempTemplate

	fmt.Printf("\n✓ Running packer build with unique AMI name...\n")
	fmt.Printf("  Command: %s\n\n", strings.Join(packerCmd, " "))

	// Execute packer build
	packerExec := exec.CommandContext(ctx, packerCmd[0], packerCmd[1:]...)
	packerExec.Dir = repoRoot
	packerExec.Stdout = os.Stdout
	packerExec.Stderr = os.Stderr

	packerErr := packerExec.Run()

	// Initialize EC2 client for instance discovery if packer failed
	if packerErr != nil {
		fmt.Printf("\n✗ Packer build failed: %v\n", packerErr)

		// Get state file path first
		stateFilePath := stateFile
		if stateFilePath == "" {
			var err error
			stateFilePath, err = state.GetDefaultStateFile()
			if err != nil {
				fmt.Printf("⚠ Could not get state file path: %v\n", err)
				return fmt.Errorf("packer build failed: %w", packerErr)
			}
		}

		// Load existing state or create new
		buildState, err := state.LoadState(stateFilePath)
		if err != nil {
			// Create new state if none exists
			buildState = &state.State{
				Region:          region,
				PostgresVersion: postgresVersion,
				GitSHA:          sha,
			}
		}

		// Try to find the packer instance by tag
		var instanceID string
		ec2Client, err := aws.NewEC2Client(ctx, region)
		if err != nil {
			fmt.Printf("⚠ Could not create EC2 client to find instance: %v\n", err)
		} else {
			fmt.Println("\n✓ Looking for packer instance...")
			instanceID, err = ec2Client.FindInstanceByTag(ctx, "packerExecutionId", executionID)
			if err != nil {
				fmt.Printf("⚠ Could not find packer instance: %v\n", err)
				fmt.Println("  Packer may have cleaned up the instance already.")
			} else {
				fmt.Printf("✓ Found packer instance: %s\n", instanceID)
			}
		}

		// Save state with execution ID (and instance ID if found)
		buildState.SetPhaseState("phase2", &state.PhaseState{
			InstanceID:  instanceID, // Will be empty string if not found
			ExecutionID: executionID,
			Timestamp:   time.Now().Format(time.RFC3339),
		})

		if err := state.SaveState(stateFilePath, buildState); err != nil {
			fmt.Printf("⚠ Could not save state: %v\n", err)
		} else {
			fmt.Printf("\n✓ State saved to: %s\n", stateFilePath)
			fmt.Printf("  Execution ID: %s\n", executionID)
			if instanceID != "" {
				fmt.Printf("  Instance ID: %s\n", instanceID)
				fmt.Printf("\nNext steps:\n")
				fmt.Printf("  - SSH into instance: pg-ami-builder ssh\n")
				fmt.Printf("  - Re-run ansible: pg-ami-builder ansible-rerun phase2 --sync-files\n")
				fmt.Printf("  - Cleanup: pg-ami-builder cleanup\n")
			} else {
				fmt.Printf("\nNo instance available for debugging (already cleaned up by packer)\n")
			}
		}

		return fmt.Errorf("packer build failed: %w", packerErr)
	}

	fmt.Printf("\n✓ Packer build completed successfully!\n")
	fmt.Println("✓ Final production AMI created by packer")

	// Find AMI by execution ID tag (injected by our template rewriter)
	var amiID string
	ec2Client, err := aws.NewEC2Client(ctx, region)
	if err != nil {
		fmt.Printf("⚠ Could not create EC2 client to find AMI: %v\n", err)
	} else {
		amiID, err = ec2Client.FindAMIByTag(ctx, "packerExecutionId", executionID)
		if err != nil {
			fmt.Printf("⚠ Could not find created AMI: %v\n", err)
		} else {
			fmt.Printf("✓ AMI ID: %s\n", amiID)
		}
	}

	// Save state even if we couldn't find the AMI
	stateFilePath := stateFile
	if stateFilePath == "" {
		stateFilePath, err = state.GetDefaultStateFile()
		if err != nil {
			fmt.Printf("⚠ Could not get state file path: %v\n", err)
			fmt.Println("\n✓ Build phase 2 complete!")
			return nil
		}
	}

	// Load existing state or create new
	buildState, err := state.LoadState(stateFilePath)
	if err != nil {
		buildState = &state.State{
			Region:          region,
			PostgresVersion: postgresVersion,
			GitSHA:          sha,
		}
	}

	buildState.SetPhaseState("phase2", &state.PhaseState{
		ExecutionID: executionID,
		AMIID:       amiID, // Will be empty if not found
		Timestamp:   time.Now().Format(time.RFC3339),
	})

	if err := state.SaveState(stateFilePath, buildState); err != nil {
		fmt.Printf("⚠ Could not save state: %v\n", err)
	} else {
		fmt.Printf("✓ State saved to: %s\n", stateFilePath)
	}

	fmt.Println("\n✓ Build phase 2 complete!")
	if amiID != "" {
		fmt.Printf("\nProduction AMI ready: %s\n", amiID)
	} else {
		fmt.Printf("\nNote: AMI ID not automatically detected. You can manually add it to:\n")
		fmt.Printf("  %s\n", stateFilePath)
	}
	return nil
}

func init() {
	rootCmd.AddCommand(buildCmd)
	buildCmd.AddCommand(buildPhase1Cmd)
	buildCmd.AddCommand(buildPhase2Cmd)

	// Phase 1 flags
	buildPhase1Cmd.Flags().StringVar(&postgresVersion, "postgres-version", "", "PostgreSQL major version (required)")
	buildPhase1Cmd.MarkFlagRequired("postgres-version")
	buildPhase1Cmd.Flags().StringVar(&region, "region", "us-east-1", "AWS region")
	buildPhase1Cmd.Flags().BoolVar(&createAMI, "create-ami", false, "Create AMI on success")
	buildPhase1Cmd.Flags().StringSliceVar(&ansibleArgs, "ansible-args", []string{}, "Additional ansible arguments")
	buildPhase1Cmd.Flags().StringVar(&instanceType, "instance-type", "c6g.4xlarge", "EC2 instance type")
	buildPhase1Cmd.Flags().StringVar(&stateFile, "state-file", "", "Custom state file path")

	// Phase 2 flags
	buildPhase2Cmd.Flags().StringVar(&sourceAMI, "source-ami", "", "Stage-1 AMI ID (optional, reads from state if not provided)")
	buildPhase2Cmd.Flags().StringVar(&postgresVersion, "postgres-version", "", "PostgreSQL major version (required)")
	buildPhase2Cmd.MarkFlagRequired("postgres-version")
	buildPhase2Cmd.Flags().StringVar(&region, "region", "us-east-1", "AWS region")
	buildPhase2Cmd.Flags().BoolVar(&createAMI, "create-ami", false, "Create AMI on success")
	buildPhase2Cmd.Flags().StringVar(&instanceType, "instance-type", "c6g.4xlarge", "EC2 instance type")
	buildPhase2Cmd.Flags().StringVar(&stateFile, "state-file", "", "Custom state file path")
	buildPhase2Cmd.Flags().StringVar(&gitSHA, "git-sha", "", "Git SHA for nix packages")
}
