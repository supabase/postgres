package nix

import (
	"fmt"
	"os"
	"os/exec"
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

	// Call sbomnix
	cmd := exec.Command(w.SbomnixPath, derivationPath, fmt.Sprintf("--spdx=%s", outputPath))
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	if err := cmd.Run(); err != nil {
		return fmt.Errorf("sbomnix failed: %w", err)
	}

	return nil
}
