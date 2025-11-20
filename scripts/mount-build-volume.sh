#!/usr/bin/env bash
# Mount temporary build volume for stage 2 nix operations
# Uses bind mount so nix operations transparently use the larger temp volume

set -o errexit
set -o pipefail
set -o xtrace

echo "=== Setting up temporary build volume for Nix ==="

echo "Formatting build volume /dev/xvdc..."
sudo mkfs.ext4 -F -O ^has_journal /dev/xvdc

echo "Creating mount point /mnt/nix-temp..."
sudo mkdir -p /mnt/nix-temp

echo "Mounting /dev/xvdc to /mnt/nix-temp..."
sudo mount /dev/xvdc /mnt/nix-temp

echo "Setting permissions on /mnt/nix-temp..."
sudo chmod 755 /mnt/nix-temp

echo "Creating /nix directory..."
sudo mkdir -p /nix

echo "Bind mounting /mnt/nix-temp over /nix..."
sudo mount --bind /mnt/nix-temp /nix

echo ""
echo "✓ Build volume setup complete"
echo "  Temp volume: /mnt/nix-temp (40 GB)"
echo "  Bind mount: /nix -> /mnt/nix-temp"
echo "  Nix will be installed to /nix (transparently using temp volume)"
df -h /nix
