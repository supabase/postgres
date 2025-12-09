package main

import (
	"flag"
	"fmt"
	"log"
	"os"

	"github.com/supabase/postgres/nix/packages/sbom/internal/merge"
	"github.com/supabase/postgres/nix/packages/sbom/internal/nix"
	"github.com/supabase/postgres/nix/packages/sbom/internal/ubuntu"
)

func main() {
	if len(os.Args) < 2 {
		printUsage()
		os.Exit(1)
	}

	subcommand := os.Args[1]

	switch subcommand {
	case "ubuntu":
		ubuntuCommand(os.Args[2:])
	case "nix":
		nixCommand(os.Args[2:])
	case "combined":
		combinedCommand(os.Args[2:])
	case "help", "--help", "-h":
		printUsage()
	default:
		fmt.Printf("Unknown subcommand: %s\n\n", subcommand)
		printUsage()
		os.Exit(1)
	}
}

func printUsage() {
	fmt.Println("sbom - SPDX SBOM generator for Ubuntu and Nix systems")
	fmt.Println()
	fmt.Println("Usage:")
	fmt.Println("  sbom <subcommand> [flags]")
	fmt.Println()
	fmt.Println("Subcommands:")
	fmt.Println("  ubuntu     Generate Ubuntu-only SBOM")
	fmt.Println("  nix        Generate Nix-only SBOM")
	fmt.Println("  combined   Generate and merge both Ubuntu and Nix SBOMs")
	fmt.Println("  help       Show this help message")
	fmt.Println()
	fmt.Println("Run 'sbom <subcommand> --help' for subcommand-specific help")
}

func ubuntuCommand(args []string) {
	fs := flag.NewFlagSet("ubuntu", flag.ExitOnError)
	outputFile := fs.String("output", "ubuntu-sbom.spdx.json", "Output file path")
	includeFiles := fs.Bool("include-files", false, "Include file checksums for each package")
	progress := fs.Bool("progress", true, "Show progress indicators")
	noProgress := fs.Bool("no-progress", false, "Disable progress indicators")

	fs.Usage = func() {
		fmt.Println("Usage: sbom ubuntu [flags]")
		fmt.Println()
		fmt.Println("Generate Ubuntu-only SBOM")
		fmt.Println()
		fmt.Println("Flags:")
		fs.PrintDefaults()
	}

	if err := fs.Parse(args); err != nil {
		os.Exit(1)
	}

	showProgress := *progress && !*noProgress

	generator := ubuntu.NewGenerator(*includeFiles, showProgress)

	doc, err := generator.Generate()
	if err != nil {
		log.Fatalf("Failed to generate SBOM: %v", err)
	}

	if err := generator.Save(doc, *outputFile); err != nil {
		log.Fatalf("Failed to save SBOM: %v", err)
	}

	fmt.Printf("Ubuntu SBOM generated successfully: %s\n", *outputFile)
}

func nixCommand(args []string) {
	fs := flag.NewFlagSet("nix", flag.ExitOnError)
	outputFile := fs.String("output", "nix-sbom.spdx.json", "Output file path")

	fs.Usage = func() {
		fmt.Println("Usage: sbom nix <derivation-path> [flags]")
		fmt.Println()
		fmt.Println("Generate Nix-only SBOM using sbomnix")
		fmt.Println()
		fmt.Println("Arguments:")
		fmt.Println("  derivation-path    Path to the Nix derivation (required)")
		fmt.Println()
		fmt.Println("Flags:")
		fs.PrintDefaults()
	}

	if err := fs.Parse(args); err != nil {
		os.Exit(1)
	}

	if fs.NArg() < 1 {
		fmt.Println("Error: derivation path required")
		fmt.Println()
		fs.Usage()
		os.Exit(1)
	}

	derivationPath := fs.Arg(0)

	// Use sbomnix from PATH
	wrapper := nix.NewWrapper("sbomnix")

	if err := wrapper.Generate(derivationPath, *outputFile); err != nil {
		log.Fatalf("Failed to generate Nix SBOM: %v", err)
	}

	fmt.Printf("Nix SBOM generated successfully: %s\n", *outputFile)
}

func combinedCommand(args []string) {
	fs := flag.NewFlagSet("combined", flag.ExitOnError)
	nixTarget := fs.String("nix-target", "", "Path to Nix derivation (required)")
	outputFile := fs.String("output", "merged-sbom.spdx.json", "Output file path")
	includeFiles := fs.Bool("include-files", false, "Include file checksums for Ubuntu packages")
	progress := fs.Bool("progress", true, "Show progress indicators")
	noProgress := fs.Bool("no-progress", false, "Disable progress indicators")

	fs.Usage = func() {
		fmt.Println("Usage: sbom combined --nix-target <derivation> [flags]")
		fmt.Println()
		fmt.Println("Generate and merge both Ubuntu and Nix SBOMs")
		fmt.Println()
		fmt.Println("Flags:")
		fs.PrintDefaults()
	}

	if err := fs.Parse(args); err != nil {
		os.Exit(1)
	}

	if *nixTarget == "" {
		fmt.Println("Error: --nix-target is required")
		fmt.Println()
		fs.Usage()
		os.Exit(1)
	}

	showProgress := *progress && !*noProgress

	// Create temporary directory
	tmpDir, err := os.MkdirTemp("", "sbom-combined-*")
	if err != nil {
		log.Fatalf("Failed to create temp directory: %v", err)
	}
	defer os.RemoveAll(tmpDir)

	ubuntuSBOM := fmt.Sprintf("%s/ubuntu-sbom.spdx.json", tmpDir)
	nixSBOM := fmt.Sprintf("%s/nix-sbom.spdx.json", tmpDir)

	// Generate Ubuntu SBOM
	fmt.Println("Generating Ubuntu SBOM...")
	ubuntuGen := ubuntu.NewGenerator(*includeFiles, showProgress)
	ubuntuDoc, err := ubuntuGen.Generate()
	if err != nil {
		log.Fatalf("Failed to generate Ubuntu SBOM: %v", err)
	}
	if err := ubuntuGen.Save(ubuntuDoc, ubuntuSBOM); err != nil {
		log.Fatalf("Failed to save Ubuntu SBOM: %v", err)
	}

	// Generate Nix SBOM
	fmt.Println("Generating Nix SBOM...")
	nixWrapper := nix.NewWrapper("sbomnix")
	if err := nixWrapper.Generate(*nixTarget, nixSBOM); err != nil {
		log.Fatalf("Failed to generate Nix SBOM: %v", err)
	}

	// Merge SBOMs
	fmt.Println("Merging SBOMs...")
	merger := merge.NewMerger()
	mergedDoc, err := merger.Merge(ubuntuSBOM, nixSBOM)
	if err != nil {
		log.Fatalf("Failed to merge SBOMs: %v", err)
	}

	if err := merger.Save(mergedDoc, *outputFile); err != nil {
		log.Fatalf("Failed to save merged SBOM: %v", err)
	}

	fmt.Printf("Merged SBOM generated successfully: %s\n", *outputFile)
}
