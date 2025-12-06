#!/bin/bash
# Baseline Validation Check
#
# This script validates that the machine matches the committed baseline
# specifications using supascan (pre-installed via nix profile).
#
# Usage: cis_baseline_check.sh [baselines-dir]

set -euo pipefail

BASELINES_DIR="${1:-/tmp/ansible-playbook/audit-specs/baselines}"

echo "============================================================"
echo "Baseline Validation"
echo "============================================================"
echo ""
echo "Baselines directory: $BASELINES_DIR"
echo ""

# Check baselines directory exists
if [[ ! -d $BASELINES_DIR ]]; then
  echo "ERROR: Baselines directory not found: $BASELINES_DIR"
  exit 1
fi

# Source nix environment
if [[ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
  # shellcheck source=/dev/null
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi

# Verify supascan is available
if ! command -v supascan &>/dev/null; then
  echo "ERROR: supascan not found. It should be pre-installed via nix profile."
  exit 1
fi

# Run supascan validate
exec supascan validate --verbose "$BASELINES_DIR"
