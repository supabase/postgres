package config

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"gopkg.in/yaml.v3"
)

// Config represents the complete configuration for the scanner, including exclusions
// and overrides. It supports a three-layer precedence model:
// 1. Hardcoded defaults (in defaults.go)
// 2. Config file (YAML)
// 3. CLI flags (highest precedence)
type Config struct {
	// Paths to exclude from scanning (glob patterns supported)
	Paths []string `yaml:"paths,omitempty"`

	// Kernel parameters to exclude from scanning
	KernelParams []string `yaml:"kernelParams,omitempty"`

	// Scanner types to disable (e.g., "port", "process")
	DisabledScanners []string `yaml:"disabledScanners,omitempty"`

	// OverridePaths allows CLI to remove default path exclusions
	OverridePaths []string `yaml:"-"`

	// OverrideKernelParams allows CLI to remove default kernel param exclusions
	OverrideKernelParams []string `yaml:"-"`
}

// CLIOptions represents command-line flags that can override configuration.
// These flags take precedence over both defaults and config files.
type CLIOptions struct {
	// IncludeDynamic removes dynamic kernel params from exclusions
	IncludeDynamic bool

	// IncludePorts enables port scanning (removes "port" from DisabledScanners)
	IncludePorts bool

	// IncludeProcesses enables process scanning (removes "process" from DisabledScanners)
	IncludeProcesses bool
}

// Load reads configuration from defaults, optional config file, and CLI options.
// Precedence: CLI flags > Config file > Hardcoded defaults
func Load(configPath string, opts CLIOptions) (*Config, error) {
	// Start with default exclusions
	cfg := DefaultExclusions

	// If a config file is specified, merge it with defaults
	if configPath != "" {
		fileCfg, err := loadFile(configPath)
		if err != nil {
			return nil, fmt.Errorf("failed to load config file: %w", err)
		}
		cfg = merge(cfg, fileCfg)
	}

	// Apply CLI overrides (highest precedence)
	if opts.IncludeDynamic {
		// Remove all dynamic kernel params from the default list
		dynamicParams := []string{
			"fs.dentry-state",
			"fs.file-nr",
			"fs.inode-nr",
			"fs.inode-state",
			"kernel.random.uuid",
			"kernel.random.boot_id",
			"kernel.ns_last_pid",
			"kernel.pty.nr",
		}
		cfg.KernelParams = removeItems(cfg.KernelParams, dynamicParams)
	}

	if opts.IncludePorts {
		cfg.DisabledScanners = removeItems(cfg.DisabledScanners, []string{"port"})
	}

	if opts.IncludeProcesses {
		cfg.DisabledScanners = removeItems(cfg.DisabledScanners, []string{"process"})
	}

	return &cfg, nil
}

// loadFile reads and parses a YAML configuration file.
func loadFile(path string) (Config, error) {
	var cfg Config

	data, err := os.ReadFile(path)
	if err != nil {
		return cfg, fmt.Errorf("failed to read config file: %w", err)
	}

	if err := yaml.Unmarshal(data, &cfg); err != nil {
		return cfg, fmt.Errorf("failed to parse config file: %w", err)
	}

	return cfg, nil
}

// merge combines two configs, with the file config adding to (not replacing) the base.
func merge(base, file Config) Config {
	result := base

	// Append file exclusions to base exclusions (additive)
	result.Paths = append(result.Paths, file.Paths...)
	result.KernelParams = append(result.KernelParams, file.KernelParams...)
	result.DisabledScanners = append(result.DisabledScanners, file.DisabledScanners...)

	return result
}

// removeItems removes all occurrences of items from slice.
func removeItems(slice []string, itemsToRemove []string) []string {
	result := make([]string, 0, len(slice))
	removeMap := make(map[string]bool)
	for _, item := range itemsToRemove {
		removeMap[item] = true
	}

	for _, item := range slice {
		if !removeMap[item] {
			result = append(result, item)
		}
	}

	return result
}

// IsPathExcluded checks if a given path matches any exclusion pattern.
// Supports glob patterns (*, ?, []).
func (c *Config) IsPathExcluded(path string) bool {
	for _, pattern := range c.Paths {
		matched, err := filepath.Match(pattern, path)
		if err != nil {
			// Invalid pattern, skip
			continue
		}
		if matched {
			return true
		}

		// Also check if path is under a directory pattern
		// e.g., /proc/* should match /proc/cpuinfo
		if strings.HasSuffix(pattern, "/*") {
			dir := strings.TrimSuffix(pattern, "/*")
			if strings.HasPrefix(path, dir+"/") {
				return true
			}
		}
	}
	return false
}

// IsKernelParamExcluded checks if a given kernel parameter matches any exclusion pattern.
// Supports glob patterns for wildcard matching.
func (c *Config) IsKernelParamExcluded(param string) bool {
	for _, pattern := range c.KernelParams {
		// Simple glob support for patterns like net.netfilter.*_conntrack_count
		if strings.Contains(pattern, "*") {
			matched, err := filepath.Match(pattern, param)
			if err != nil {
				continue
			}
			if matched {
				return true
			}
		} else {
			// Exact match
			if param == pattern {
				return true
			}
		}
	}
	return false
}

// IsScannerDisabled checks if a given scanner type is disabled in the configuration.
func (c *Config) IsScannerDisabled(scannerType string) bool {
	for _, disabled := range c.DisabledScanners {
		if disabled == scannerType {
			return true
		}
	}
	return false
}
