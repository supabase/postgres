package main

import (
	"fmt"
	"os"
	"path/filepath"
	"syscall"

	"github.com/spf13/cobra"

	"github.com/supabase/supascan/internal/discovery"
)

var discoverRoot string

var discoverCmd = &cobra.Command{
	Use:   "discover <policy-file>",
	Short: "Scan the filesystem for permission and ownership drift",
	Args:  cobra.ExactArgs(1),
	RunE:  runDiscover,
}

func init() {
	discoverCmd.Flags().StringVar(&discoverRoot, "root", "/", "Filesystem root to scan")
	rootCmd.AddCommand(discoverCmd)
}

// escalate replaces the process with `sudo -n supascan discover ...` so the
// walk can read every directory. It uses fixed paths and a minimal
// environment, and -n fails instead of prompting.
func escalate() error {
	if os.Geteuid() == 0 {
		return nil
	}
	self, err := os.Executable()
	if err == nil {
		self, err = filepath.EvalSymlinks(self)
	}
	if err != nil {
		return err
	}
	argv := append([]string{"sudo", "-n", "--", self}, os.Args[1:]...)
	return syscall.Exec("/usr/bin/sudo", argv, []string{"PATH=/usr/sbin:/usr/bin:/sbin:/bin"})
}

func runDiscover(cmd *cobra.Command, args []string) error {
	if err := escalate(); err != nil {
		return fmt.Errorf("re-run under sudo: %w", err)
	}
	policy, err := discovery.LoadPolicy(args[0])
	if err != nil {
		return err
	}
	findings, err := discovery.Scan(discoverRoot, policy)
	if err != nil {
		return err
	}
	for _, f := range findings {
		fmt.Fprintln(cmd.OutOrStdout(), f)
	}
	if len(findings) > 0 {
		cmd.SilenceUsage = true
		return fmt.Errorf("%d finding(s)", len(findings))
	}
	return nil
}
