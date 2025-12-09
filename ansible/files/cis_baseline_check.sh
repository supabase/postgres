#!/bin/bash
# Baseline Validation Check
#
# This script validates that the machine matches the committed baseline
# specifications using the supascan tool from the nix flake.
#
# Usage: cis_baseline_check.sh [baselines-dir] [flake-path]

set -euo pipefail

BASELINES_DIR="${1:-/tmp/ansible-playbook/audit-specs/baselines}"
FLAKE_PATH="${2:-/tmp/ansible-playbook}"

echo "============================================================"
echo "Baseline Validation Setup"
echo "============================================================"
echo ""
echo "Baselines directory: $BASELINES_DIR"
echo "Flake path: $FLAKE_PATH"
echo ""

# Check baselines directory exists
if [[ ! -d $BASELINES_DIR ]]; then
  echo "ERROR: Baselines directory not found: $BASELINES_DIR"
  exit 1
fi

# Source nix environment
if [[ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi

# Install supascan from the flake if not already installed
echo "Installing supascan from flake..."
if ! command -v supascan &>/dev/null; then
  nix profile install "${FLAKE_PATH}#supascan" --accept-flake-config
  echo "✓ supascan installed"
else
  echo "✓ supascan already available"
fi

echo ""

# Run supascan validate
# The tool handles all the logic for running specs and categorizing results
exec supascan validate --verbose "$BASELINES_DIR"
