package cmd

import (
	"fmt"

	"github.com/spf13/cobra"
)

var Version = "dev"

var versionCmd = &cobra.Command{
	Use:   "version",
	Short: "Print version information",
	Run: func(cmd *cobra.Command, args []string) {
		fmt.Printf("pg-ami-builder version %s\n", Version)
	},
}

func init() {
	rootCmd.AddCommand(versionCmd)
}
