#!/usr/bin/env bash
# Copy nix store from temporary build volume back to root filesystem
# Includes size check and fails build if it won't fit

set -o errexit
set -o pipefail
set -o xtrace

echo "=== Migrating Nix store from temp volume to root filesystem ==="

# Stop nix daemon before unmounting
echo "Stopping nix-daemon..."
sudo systemctl stop nix-daemon.service || true
sudo systemctl stop nix-daemon.socket || true

# Get size of nix store on temp volume (in bytes)
echo ""
echo "Checking nix store size..."
NIX_STORE_SIZE=$(sudo du -sb /mnt/nix-temp | cut -f1)
NIX_STORE_SIZE_GB=$(awk "BEGIN {printf \"%.2f\", $NIX_STORE_SIZE / 1024 / 1024 / 1024}")
echo "Nix store size: ${NIX_STORE_SIZE_GB} GB (${NIX_STORE_SIZE} bytes)"

# Get available space on root filesystem (in bytes)
# Check the actual root filesystem, not the bind mount
ROOT_FS_DEVICE=$(df / | tail -1 | awk '{print $1}')
ROOT_AVAILABLE=$(df -B1 / | tail -1 | awk '{print $4}')
ROOT_AVAILABLE_GB=$(awk "BEGIN {printf \"%.2f\", $ROOT_AVAILABLE / 1024 / 1024 / 1024}")
echo "Root filesystem (${ROOT_FS_DEVICE}) available space: ${ROOT_AVAILABLE_GB} GB (${ROOT_AVAILABLE} bytes)"

# Add 10% buffer for safety
REQUIRED_SPACE=$(awk "BEGIN {printf \"%.0f\", $NIX_STORE_SIZE * 1.1}")
REQUIRED_SPACE_GB=$(awk "BEGIN {printf \"%.2f\", $REQUIRED_SPACE / 1024 / 1024 / 1024}")
echo "Required space (with 10% buffer): ${REQUIRED_SPACE_GB} GB (${REQUIRED_SPACE} bytes)"

# Check if there's enough space
echo ""
if [ "$ROOT_AVAILABLE" -lt "$REQUIRED_SPACE" ]; then
    echo "======================================"
    echo "ERROR: Not enough space on root filesystem!"
    echo "======================================"
    echo "  Nix store size:       ${NIX_STORE_SIZE_GB} GB"
    echo "  Required (+ buffer):  ${REQUIRED_SPACE_GB} GB"
    echo "  Available on root:    ${ROOT_AVAILABLE_GB} GB"
    SHORTFALL=$(awk "BEGIN {printf \"%.2f\", ($REQUIRED_SPACE - $ROOT_AVAILABLE) / 1024 / 1024 / 1024}")
    echo "  Shortfall:            ${SHORTFALL} GB"
    echo ""
    echo "Build FAILED: Nix store is too large to fit on the root volume."
    echo "Consider increasing the root volume size in amazon-arm64-nix.pkr.hcl"
    exit 1
fi

echo "✓ Space check passed. Sufficient space available."
echo ""

# Unmount the bind mount
echo "Unmounting bind mount /nix..."
sudo umount /nix

echo "/nix now shows original (empty) directory on root filesystem"
ls -la /nix/ || true

echo ""
echo "Copying nix store from temp volume to root filesystem..."
echo "This may take several minutes..."
sudo rsync -aHAXS --info=progress2 /mnt/nix-temp/ /nix/

# Verify the copy
COPIED_SIZE=$(sudo du -sb /nix | cut -f1)
COPIED_SIZE_GB=$(awk "BEGIN {printf \"%.2f\", $COPIED_SIZE / 1024 / 1024 / 1024}")
echo ""
echo "Copy verification:"
echo "  Original size: ${NIX_STORE_SIZE_GB} GB (${NIX_STORE_SIZE} bytes)"
echo "  Copied size:   ${COPIED_SIZE_GB} GB (${COPIED_SIZE} bytes)"

# Allow small differences due to filesystem overhead
SIZE_DIFF=$(awk "BEGIN {x = $NIX_STORE_SIZE - $COPIED_SIZE; print (x < 0 ? -x : x)}")
SIZE_DIFF_PERCENT=$(awk "BEGIN {printf \"%.2f\", $SIZE_DIFF * 100 / $NIX_STORE_SIZE}")

# Check if difference is greater than 1%
if awk "BEGIN {exit !($SIZE_DIFF_PERCENT > 1)}"; then
    echo "ERROR: Significant size mismatch after copy (${SIZE_DIFF_PERCENT}% difference)!"
    exit 1
fi

echo "✓ Copy verified (size difference: ${SIZE_DIFF_PERCENT}%)"

# Unmount temp volume (will be discarded by packer)
echo ""
echo "Unmounting temp volume /mnt/nix-temp..."
sudo umount /mnt/nix-temp
sudo rmdir /mnt/nix-temp

echo ""
echo "=== Nix Store Migration Complete ==="
echo "Final location: /nix (on root filesystem)"
df -h /nix
echo ""
echo "Nix store contents:"
sudo du -sh /nix/store

# Restart nix daemon
echo ""
echo "Restarting nix-daemon..."
sudo systemctl start nix-daemon.socket || true
sudo systemctl start nix-daemon.service || true

echo ""
echo "✓ All done! Nix store successfully migrated to root filesystem."
