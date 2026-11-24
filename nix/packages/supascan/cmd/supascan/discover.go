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
	Long: `Walk the filesystem and report paths that goss specs cannot cover because
they are not listed: setuid or setgid files outside the allowlist, world-writable
paths other than sticky directories, group-writable paths without an exception,
owner or group ids with no passwd or group entry, and modes outside the allowlist
under the policy roots.

Exits non-zero when anything is reported. Run as root to read every directory.

Examples:
  sudo supascan discover audit-specs/baselines/ami-build-amd64/file-discovery.yml

  # Scan an extracted image
  sudo supascan discover --root /mnt/image policy.yml
`,
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
		return fmt.Errorf("failed to load policy: %w", err)
	}

	res, err := discovery.Scan(context.Background(), discoverRoot, policy)
	if err != nil {
		return fmt.Errorf("scan failed: %w", err)
	}

	out := cmd.OutOrStdout()
	for _, e := range res.Errors {
		fmt.Fprintf(out, "warning: %s\n", e)
	}
	for _, f := range res.Findings {
		fmt.Fprintln(out, f)
	}
	fmt.Fprintf(out, "%d finding(s) in %d entries\n", len(res.Findings), res.Scanned)

	if len(res.Findings) > 0 {
		cmd.SilenceUsage = true
		cmd.SilenceErrors = true
		return fmt.Errorf("%d finding(s)", len(res.Findings))
	}
	return nil
}
