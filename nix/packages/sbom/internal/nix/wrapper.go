package nix

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/supabase/postgres/nix/packages/sbom/internal/merge"
)

type Wrapper struct {
	SbomnixPath string
}

func NewWrapper(sbomnixPath string) *Wrapper {
	return &Wrapper{
		SbomnixPath: sbomnixPath,
	}
}

func (w *Wrapper) Generate(derivationPath, outputPath string) error {
	// Validate derivation path exists
	if _, err := os.Stat(derivationPath); err != nil {
		return fmt.Errorf("derivation path does not exist: %s", derivationPath)
	}

	// Validate and sanitize outputPath to prevent path traversal
	cleanOutputPath := filepath.Clean(outputPath)
	if strings.Contains(cleanOutputPath, "..") {
		return fmt.Errorf("invalid output path: path traversal detected")
	}

	// Call sbomnix
	cmd := exec.Command(w.SbomnixPath, derivationPath, fmt.Sprintf("--spdx=%s", cleanOutputPath))
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	if err := cmd.Run(); err != nil {
		return fmt.Errorf("sbomnix failed: %w", err)
	}

	return nil
}

// GenerateMultiple generates SBOMs for multiple derivation paths and merges them
func (w *Wrapper) GenerateMultiple(derivationPaths []string, outputPath string) error {
	if len(derivationPaths) == 0 {
		return fmt.Errorf("no derivation paths provided")
	}

	if len(derivationPaths) == 1 {
		return w.Generate(derivationPaths[0], outputPath)
	}

	// Validate and sanitize outputPath to prevent path traversal
	cleanOutputPath := filepath.Clean(outputPath)
	if strings.Contains(cleanOutputPath, "..") {
		return fmt.Errorf("invalid output path: path traversal detected")
	}

	// Create temporary directory for individual SBOMs
	tmpDir, err := os.MkdirTemp("", "sbom-nix-multi-*")
	if err != nil {
		return fmt.Errorf("failed to create temp directory: %w", err)
	}
	defer os.RemoveAll(tmpDir)

	// Generate individual SBOMs
	var spdxFiles []string
	for i, derivationPath := range derivationPaths {
		// Validate derivation path exists
		if _, err := os.Stat(derivationPath); err != nil {
			fmt.Printf("Warning: derivation path does not exist, skipping: %s\n", derivationPath)
			continue
		}

		tmpOutput := filepath.Join(tmpDir, fmt.Sprintf("sbom-%d.spdx.json", i))

		fmt.Printf("Generating SBOM for %s...\n", derivationPath)
		cmd := exec.Command(w.SbomnixPath, derivationPath, fmt.Sprintf("--spdx=%s", tmpOutput))
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr

		if err := cmd.Run(); err != nil {
			fmt.Printf("Warning: sbomnix failed for %s: %v\n", derivationPath, err)
			continue
		}

		spdxFiles = append(spdxFiles, tmpOutput)
	}

	if len(spdxFiles) == 0 {
		return fmt.Errorf("no SBOMs generated successfully")
	}

	// Merge all SBOMs
	fmt.Printf("Merging %d SBOMs...\n", len(spdxFiles))
	merger := merge.NewMerger()
	mergedDoc, err := merger.MergeMultipleNix(spdxFiles)
	if err != nil {
		return fmt.Errorf("failed to merge SBOMs: %w", err)
	}

	// Save merged document
	if err := merger.Save(mergedDoc, cleanOutputPath); err != nil {
		return fmt.Errorf("failed to save merged SBOM: %w", err)
	}

	return nil
}
