#!/usr/bin/env bash

set -euo pipefail

DEVICE=${1:-}
MOUNT_POINT=${2:-}

if [[ -z "$DEVICE" || -z "$MOUNT_POINT" ]]; then
  echo "Usage: $0 <device> <mount_point>"
  echo "Example: sudo ./mount-volume.sh /dev/nvme1n1 /data/150008"
  exit 1
fi

#  Mount a block device to a specified mount point
#  If the device is not formatted, format it as ext4
#  Set ownership to postgres:postgres and permissions to 750
#  Add the mount entry to /etc/fstab for persistence across reboots

OWNER="postgres:postgres"
PERMISSIONS="750"
FSTYPE="ext4"
MOUNT_OPTS="defaults"
FSTAB_FILE="/etc/fstab"

if [ ! -b "$DEVICE" ]; then
  echo "Error: Block device '$DEVICE' does not exist."
  exit 2
fi

if ! blkid "$DEVICE" >/dev/null 2>&1; then
  echo "Device $DEVICE appears unformatted. Formatting as $FSTYPE..."
  mkfs."$FSTYPE" -F "$DEVICE"
else
  echo "$DEVICE already has a filesystem — skipping format."
fi

mkdir -p "$MOUNT_POINT"

e2fsck -pf "$DEVICE"

if ! mountpoint -q "$MOUNT_POINT"; then
  echo "Mounting $DEVICE to $MOUNT_POINT"
  mount -t "$FSTYPE" -o "$MOUNT_OPTS" "$DEVICE" "$MOUNT_POINT"
else
  echo "$MOUNT_POINT is already mounted"
fi

echo "Setting ownership and permissions on $MOUNT_POINT"
chown "$OWNER" "$MOUNT_POINT"
chmod "$PERMISSIONS" "$MOUNT_POINT"

UUID=$(blkid -s UUID -o value "$DEVICE")
FSTAB_LINE="UUID=$UUID  $MOUNT_POINT  $FSTYPE  $MOUNT_OPTS  0  2"

if ! grep -q "$UUID" "$FSTAB_FILE"; then
  echo "Adding $FSTAB_LINE to $FSTAB_FILE"
  echo "$FSTAB_LINE" >> "$FSTAB_FILE"
else
  echo "UUID $UUID already in $FSTAB_FILE — skipping"
fi

echo "Mounted $DEVICE at $MOUNT_POINT with postgres:postgres and mode $PERMISSIONS"
