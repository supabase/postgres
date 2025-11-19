package packer

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

// GetPackerTemplate returns the packer template path for a phase
func GetPackerTemplate(phase string) string {
	if phase == "phase1" {
		return "amazon-arm64-nix.pkr.hcl"
	}
	return "stage2-nix-psql.pkr.hcl"
}

// RewriteTemplateWithUniqueAMI creates a temporary copy of the template with unique AMI name
// For phase2, also replaces source_ami_filter with direct source_ami if sourceAMI is provided
func RewriteTemplateWithUniqueAMI(templatePath, executionID, sourceAMI string) (string, func(), error) {
	// Read the original template
	content, err := os.ReadFile(templatePath)
	if err != nil {
		return "", nil, fmt.Errorf("failed to read template: %w", err)
	}

	modified := string(content)

	// For phase2: replace source_ami_filter with direct source_ami FIRST
	// Do this before ami_name modification to avoid conflicts
	if sourceAMI != "" {
		// Remove the entire source_ami_filter block (with nested braces)
		// Match from source_ami_filter to a closing brace at line start (same indentation)
		filterPattern := regexp.MustCompile(`(?m)source_ami_filter\s*\{[^}]*\{[^}]*\}[^}]*\}`)
		modified = filterPattern.ReplaceAllString(modified, fmt.Sprintf(`source_ami = "%s"`, sourceAMI))
	}

	// Modify ami_name to append execution ID
	// Pattern matches: ami_name = "something-${var.postgres-version}-stage-1"
	// or: ami_name = "something-${var.postgres-version}"
	pattern := regexp.MustCompile(`(ami_name\s*=\s*"[^"]+")`)
	modified = pattern.ReplaceAllStringFunc(modified, func(match string) string {
		// Insert execution ID before the closing quote
		return strings.TrimSuffix(match, `"`) + `-${var.packer-execution-id}"`
	})

	// Add packerExecutionId to AMI tags (not run_tags)
	// Find the tags = { block (after run_tags) and inject packerExecutionId
	tagsPattern := regexp.MustCompile(`(?s)(tags\s*=\s*\{)([^}]*creator\s*=\s*"packer"[^}]*)(\})`)
	modified = tagsPattern.ReplaceAllStringFunc(modified, func(match string) string {
		// Check if packerExecutionId already exists in this tags block
		if strings.Contains(match, "packerExecutionId") {
			return match // Already has it
		}
		// Insert packerExecutionId after the opening brace
		parts := tagsPattern.FindStringSubmatch(match)
		if len(parts) == 4 {
			return parts[1] + "\n    packerExecutionId = \"${var.packer-execution-id}\"" + parts[2] + parts[3]
		}
		return match
	})

	// Create temp file
	tempDir := os.TempDir()
	tempFile := filepath.Join(tempDir, fmt.Sprintf("packer-%s-%s", executionID, filepath.Base(templatePath)))

	if err := os.WriteFile(tempFile, []byte(modified), 0o644); err != nil {
		return "", nil, fmt.Errorf("failed to write temp template: %w", err)
	}

	// Return cleanup function
	cleanup := func() {
		os.Remove(tempFile)
	}

	return tempFile, cleanup, nil
}

// BuildPackerCommand constructs the packer build command
func BuildPackerCommand(phase, postgresVersion, executionID string, extraVars map[string]string) []string {
	template := GetPackerTemplate(phase)

	args := []string{
		"packer",
		"build",
		"-on-error=abort", // Keep instance running on failure for debugging
		"-var", fmt.Sprintf("postgres-version=%s", postgresVersion),
		"-var", fmt.Sprintf("packer-execution-id=%s", executionID),
	}

	// Add any extra variables
	for key, value := range extraVars {
		args = append(args, "-var", fmt.Sprintf("%s=%s", key, value))
	}

	args = append(args, template)

	return args
}
