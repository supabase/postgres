package main

import (
	"context"
	"fmt"

	"github.com/spf13/cobra"

	"github.com/supabase/supascan/internal/discovery"
)

var discoverRoot string

var discoverCmd = &cobra.Command{
	Use:   "discover <policy-file>",
	Short: "Scan the filesystem for permission and ownership drift",
	Long: `Walk the filesystem and report setuid or setgid files outside the allowlist,
world-writable paths other than sticky directories, group-writable paths, owner or
group ids with no passwd or group entry, and modes outside the allowlist under the
policy roots. Exits non-zero when anything is reported. Run as root.`,
	Args: cobra.ExactArgs(1),
	RunE: runDiscover,
}

func init() {
	discoverCmd.Flags().StringVar(&discoverRoot, "root", "/", "Filesystem root to scan")
	rootCmd.AddCommand(discoverCmd)
}

func runDiscover(cmd *cobra.Command, args []string) error {
	policy, err := discovery.LoadPolicy(args[0])
	if err != nil {
		return err
	}
	findings, err := discovery.Scan(context.Background(), discoverRoot, policy)
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
