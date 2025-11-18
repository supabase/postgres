package cmd

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"
)

var rootCmd = &cobra.Command{
	Use:   "pg-ami-builder",
	Short: "Local AMI development tool for Supabase Postgres",
	Long: `pg-ami-builder is a CLI tool for iterating on AMI builds locally.

It allows developers to run individual build phases, debug ansible failures,
and quickly iterate without running full CI/CD pipelines.`,
}

// Execute runs the root command
func Execute() {
	if err := rootCmd.Execute(); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}

func init() {
	rootCmd.CompletionOptions.DisableDefaultCmd = true
}
