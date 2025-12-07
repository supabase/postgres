#!/bin/bash
# Baseline Validation Check
#
# This script validates that the machine matches the committed baseline
# specifications using supascan (pre-installed via nix profile for ubuntu user).
#
# Must be run as ubuntu user with sudo access (supascan calls sudo goss internally).
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

# Source nix environment (for ubuntu user's profile)
# shellcheck source=/dev/null
. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh

# Verify supascan is available
if ! command -v supascan &>/dev/null; then
  echo "ERROR: supascan not found in PATH"
  echo "PATH: $PATH"
  exit 1
fi

# Run supascan validate (it calls sudo goss internally for privileged checks)
exec supascan validate --verbose "$BASELINES_DIR"
