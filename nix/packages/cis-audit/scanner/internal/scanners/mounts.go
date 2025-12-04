package scanners

import (
	"bufio"
	"context"
	"fmt"
	"os"
	"strings"

	"github.com/supabase/ubuntu-cis-audit/scanner/internal/spec"
)

// MountScanner scans all mounts from /proc/mounts.
type MountScanner struct {
	mountsPath string // For testing (default: "/proc/mounts")
	stats      ScanStats
}

func (s *MountScanner) Name() string {
	return "mounts"
}

func (s *MountScanner) IsDynamic() bool {
	return false // Mount points are relatively static
}

func (s *MountScanner) Scan(ctx context.Context, opts ScanOptions) (ScanStats, error) {
	opts.Logger.Info("Starting mount scan")

	// Get writer interface
	writer, ok := opts.Writer.(Writer)
	if !ok {
		return s.stats, fmt.Errorf("writer does not implement Writer interface")
	}

	if err := writer.StartResource("mount"); err != nil {
		return s.stats, err
	}

	// Get mounts
	mounts, err := s.getMounts(opts)
	if err != nil {
		return s.stats, err
	}

	// Add each mount to writer
	for path, mount := range mounts {
		if err := writer.Add(mount); err != nil {
			return s.stats, fmt.Errorf("failed to write mount spec for %s: %w", path, err)
		}
	}

	opts.Logger.Info("Mount scan complete", "mounts_found", len(mounts))

	return s.stats, nil
}

// getMounts reads and parses /proc/mounts
func (s *MountScanner) getMounts(opts ScanOptions) (map[string]spec.MountSpec, error) {
	mountsPath := s.mountsPath
	if mountsPath == "" {
		mountsPath = "/proc/mounts"
	}

	file, err := os.Open(mountsPath)
	if err != nil {
		return nil, fmt.Errorf("failed to open %s: %w", mountsPath, err)
	}
	defer file.Close()

	mounts := make(map[string]spec.MountSpec)
	scanner := bufio.NewScanner(file)
	lineNum := 0

	for scanner.Scan() {
		lineNum++
		line := strings.TrimSpace(scanner.Text())

		// Skip empty lines and comments
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}

		// Parse mounts line: device mountpoint fstype options dump pass
		// Fields are space-separated
		fields := strings.Fields(line)
		if len(fields) < 4 {
			// Skip malformed lines
			opts.Logger.Debug("Skipping malformed mounts line", "line", lineNum, "content", line)
			continue
		}

		device := fields[0]
		mountpoint := fields[1]
		fstype := fields[2]
		optionsStr := fields[3]

		// Parse options (comma-separated)
		var opts []string
		if optionsStr != "" {
			opts = strings.Split(optionsStr, ",")
		}

		mounts[mountpoint] = spec.MountSpec{
			Path:       mountpoint,
			Exists:     true,
			Filesystem: fstype,
			Opts:       opts,
			Source:     device,
		}
	}

	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("error reading %s: %w", mountsPath, err)
	}

	return mounts, nil
}
