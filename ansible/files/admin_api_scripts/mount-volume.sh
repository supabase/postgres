#!/usr/bin/env bash
set -euo pipefail

DEVICE=${1:-}
MOUNT_POINT=${2:-}
TIMEOUT=60    # max seconds to wait for device
INTERVAL=2    # polling interval

OWNER="postgres:postgres"
PERMISSIONS="750"
FSTYPE="ext4"
MOUNT_OPTS="defaults"
FSTAB_FILE="/etc/fstab"
LOG_TAG="mount-volume"

if [[ -z "$DEVICE" || -z "$MOUNT_POINT" ]]; then
  logger -t "$LOG_TAG" "Usage: $0 <device> <mount_point>"
  logger -t "$LOG_TAG" "Example: sudo $0 /dev/nvme1n1 /data/150008"
  exit 1
fi

if [ "$EUID" -ne 0 ]; then
  logger -t "$LOG_TAG" "Please run as root"
  exit 1
fi

logger -t "$LOG_TAG" "Waiting for block device $DEVICE to become available..."

ELAPSED=0
while true; do
  if [ -b "$DEVICE" ] && [ -s "/sys/block/$(basename $DEVICE)/size" ]; then
    logger -t "$LOG_TAG" "$DEVICE is ready"
    break
  fi

  ELAPSED=$((ELAPSED + INTERVAL))
  if [ $ELAPSED -ge $TIMEOUT ]; then
    logger -t "$LOG_TAG" "Error: $DEVICE did not become ready after $TIMEOUT seconds"
    exit 2
  fi
  sleep $INTERVAL
done

# Check if device has a filesystem
if ! blkid "$DEVICE" >/dev/null 2>&1; then
  logger -t "$LOG_TAG" "$DEVICE appears unformatted. Formatting as $FSTYPE..."
  mkfs."$FSTYPE" -F "$DEVICE"
else
  logger -t "$LOG_TAG" "$DEVICE already has a filesystem — skipping format"
  # Run e2fsck safely
  e2fsck -pf "$DEVICE" || true
fi

# Prepare mount point
mkdir -p "$MOUNT_POINT"

# Check if mount point is already used
if mountpoint -q "$MOUNT_POINT"; then
  CURRENT_DEVICE=$(findmnt -n -o SOURCE --target "$MOUNT_POINT")
  if [ "$CURRENT_DEVICE" != "$DEVICE" ]; then
    logger -t "$LOG_TAG" "Error: $MOUNT_POINT is already mounted on $CURRENT_DEVICE"
    exit 3
  else
    logger -t "$LOG_TAG" "$MOUNT_POINT is already mounted on $DEVICE"
  fi
else
  logger -t "$LOG_TAG" "Mounting $DEVICE to $MOUNT_POINT"
  mount -t "$FSTYPE" -o "$MOUNT_OPTS" "$DEVICE" "$MOUNT_POINT"
fi

# Set ownership and permissions
logger -t "$LOG_TAG" "Setting ownership to $OWNER and permissions to $PERMISSIONS"
chown "$OWNER" "$MOUNT_POINT"
chmod "$PERMISSIONS" "$MOUNT_POINT"

# Add to /etc/fstab if not present
UUID=$(blkid -s UUID -o value "$DEVICE")
FSTAB_LINE="UUID=$UUID  $MOUNT_POINT  $FSTYPE  $MOUNT_OPTS  0  2"

if ! grep -q -F "UUID=$UUID" "$FSTAB_FILE"; then
  logger -t "$LOG_TAG" "Adding $FSTAB_LINE to $FSTAB_FILE"
  echo "$FSTAB_LINE" >> "$FSTAB_FILE"
else
  logger -t "$LOG_TAG" "UUID $UUID already exists in $FSTAB_FILE — skipping"
fi

logger -t "$LOG_TAG" "Mounted $DEVICE at $MOUNT_POINT with ownership $OWNER and permissions $PERMISSIONS"
