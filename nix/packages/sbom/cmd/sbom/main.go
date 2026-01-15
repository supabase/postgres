package main

import (
	"flag"
	"fmt"
	"log"
	"os"
	"strings"

	"github.com/supabase/postgres/nix/packages/sbom/internal/merge"
	"github.com/supabase/postgres/nix/packages/sbom/internal/nix"
	"github.com/supabase/postgres/nix/packages/sbom/internal/spdx"
	"github.com/supabase/postgres/nix/packages/sbom/internal/ubuntu"
)

// stringSliceFlag allows multiple values for a single flag
type stringSliceFlag []string

func (s *stringSliceFlag) String() string {
	return strings.Join(*s, ", ")
}

func (s *stringSliceFlag) Set(value string) error {
	*s = append(*s, value)
	return nil
}

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
		fmt.Println("Usage: sbom nix <derivation-path> [derivation-path...] [flags]")
		fmt.Println()
		fmt.Println("Generate Nix-only SBOM using sbomnix")
		fmt.Println()
		fmt.Println("Arguments:")
		fmt.Println("  derivation-path    Path(s) to Nix derivation(s) (at least one required)")
		fmt.Println()
		fmt.Println("Flags:")
		fs.PrintDefaults()
	}

	if err := fs.Parse(args); err != nil {
		os.Exit(1)
	}

	if fs.NArg() < 1 {
		fmt.Println("Error: at least one derivation path required")
		fmt.Println()
		fs.Usage()
		os.Exit(1)
	}

	// Use sbomnix from PATH
	wrapper := nix.NewWrapper("sbomnix")

	if fs.NArg() == 1 {
		// Single path - use original method
		if err := wrapper.Generate(fs.Arg(0), *outputFile); err != nil {
			log.Fatalf("Failed to generate Nix SBOM: %v", err)
		}
	} else {
		// Multiple paths - use new method
		paths := fs.Args()
		if err := wrapper.GenerateMultiple(paths, *outputFile); err != nil {
			log.Fatalf("Failed to generate Nix SBOM: %v", err)
		}
	}

	fmt.Printf("Nix SBOM generated successfully: %s\n", *outputFile)
}

func combinedCommand(args []string) {
	fs := flag.NewFlagSet("combined", flag.ExitOnError)
	var nixTargets stringSliceFlag
	fs.Var(&nixTargets, "nix-target", "Path to Nix derivation (can be specified multiple times)")
	outputFile := fs.String("output", "merged-sbom.spdx.json", "Output file path")
	includeFiles := fs.Bool("include-files", false, "Include file checksums for Ubuntu packages")
	progress := fs.Bool("progress", true, "Show progress indicators")
	noProgress := fs.Bool("no-progress", false, "Disable progress indicators")
	nixOnly := fs.Bool("nix-only", false, "Generate Nix-only SBOM (skip Ubuntu packages)")

	fs.Usage = func() {
		fmt.Println("Usage: sbom combined --nix-target <derivation> [--nix-target <derivation>...] [flags]")
		fmt.Println()
		fmt.Println("Generate and merge both Ubuntu and Nix SBOMs")
		fmt.Println()
		fmt.Println("Flags:")
		fs.PrintDefaults()
	}

	if err := fs.Parse(args); err != nil {
		os.Exit(1)
	}

	if len(nixTargets) == 0 {
		fmt.Println("Error: at least one --nix-target is required")
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

	merger := merge.NewMerger()
	nixWrapper := nix.NewWrapper("sbomnix")

	var ubuntuSBOM string
	if !*nixOnly {
		// Generate Ubuntu SBOM
		fmt.Println("Generating Ubuntu SBOM...")
		ubuntuSBOM = fmt.Sprintf("%s/ubuntu-sbom.spdx.json", tmpDir)
		ubuntuGen := ubuntu.NewGenerator(*includeFiles, showProgress)
		ubuntuDoc, err := ubuntuGen.Generate()
		if err != nil {
			log.Fatalf("Failed to generate Ubuntu SBOM: %v", err)
		}
		if err := ubuntuGen.Save(ubuntuDoc, ubuntuSBOM); err != nil {
			log.Fatalf("Failed to save Ubuntu SBOM: %v", err)
		}
	}

	// Generate Nix SBOM(s)
	fmt.Printf("Generating Nix SBOM from %d target(s)...\n", len(nixTargets))
	nixSBOM := fmt.Sprintf("%s/nix-sbom.spdx.json", tmpDir)

	if len(nixTargets) == 1 {
		if err := nixWrapper.Generate(nixTargets[0], nixSBOM); err != nil {
			log.Fatalf("Failed to generate Nix SBOM: %v", err)
		}
	} else {
		if err := nixWrapper.GenerateMultiple([]string(nixTargets), nixSBOM); err != nil {
			log.Fatalf("Failed to generate Nix SBOM: %v", err)
		}
	}

	// Merge SBOMs
	fmt.Println("Merging SBOMs...")
	var mergedDoc *spdx.Document
	if *nixOnly {
		// Load and output Nix SBOM directly
		mergedDoc, err = merger.LoadDocument(nixSBOM)
		if err != nil {
			log.Fatalf("Failed to load Nix SBOM: %v", err)
		}
	} else {
		mergedDoc, err = merger.Merge(ubuntuSBOM, nixSBOM)
		if err != nil {
			log.Fatalf("Failed to merge SBOMs: %v", err)
		}
	}

	if err := merger.Save(mergedDoc, *outputFile); err != nil {
		log.Fatalf("Failed to save merged SBOM: %v", err)
	}

	fmt.Printf("Merged SBOM generated successfully: %s\n", *outputFile)
}
