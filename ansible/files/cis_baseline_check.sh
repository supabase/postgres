#!/bin/bash
# CIS Baseline Validation Check
#
# This script validates that the machine matches the committed baseline
# specification. It's run during the image build to catch configuration
# drift before releasing an image.
#
# Usage: cis_baseline_check.sh <baseline-file> [flake-path]

set -euo pipefail

BASELINE_FILE="${1:-/tmp/ansible-playbook/audit-specs/baselines/baseline.yml}"
FLAKE_PATH="${2:-/tmp/ansible-playbook}"

echo "============================================================"
echo "CIS Baseline Validation"
echo "============================================================"
echo ""
echo "Baseline file: $BASELINE_FILE"
echo "Flake path: $FLAKE_PATH"
echo ""

# Check baseline file exists
if [[ ! -f "$BASELINE_FILE" ]]; then
    echo "ERROR: Baseline file not found: $BASELINE_FILE"
    echo ""
    echo "Make sure the baseline.yml is copied to the build machine."
    exit 1
fi

# Source nix environment for the ubuntu user
# The build runs as root but nix is installed for ubuntu
if [[ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi

# Install cis-audit from the flake if not already installed
echo "Installing cis-audit from flake..."
if ! command -v cis-audit &> /dev/null; then
    # Install cis-audit package which includes goss
    nix profile install "${FLAKE_PATH}#cis-audit" --accept-flake-config
    echo "✓ cis-audit installed"
else
    echo "✓ cis-audit already available"
fi

echo ""
echo "Running baseline validation..."
echo "------------------------------------------------------------"

# Run cis-audit with the baseline spec
# The cis-audit wrapper handles running goss with sudo
if cis-audit --spec "$BASELINE_FILE" --format documentation; then
    echo "------------------------------------------------------------"
    echo ""
    echo "✓ CIS baseline validation PASSED"
    echo "  Machine configuration matches the committed baseline."
    echo ""
    exit 0
else
    EXIT_CODE=$?
    echo "------------------------------------------------------------"
    echo ""
    echo "✗ CIS baseline validation FAILED"
    echo ""
    echo "  The machine configuration has drifted from the baseline."
    echo "  Review the failures above and either:"
    echo "    1. Fix the configuration to match the baseline, OR"
    echo "    2. Update the baseline if the change is intentional:"
    echo "       nix run .#cis-generate-spec -- audit-specs/baselines/baseline.yml"
    echo ""
    exit $EXIT_CODE
fi
