#! /usr/bin/env bash

set -euo pipefail

VOLUME_TYPE=${1:-data}

if pgrep resizefs; then
    echo "resize2fs is already running"
    exit 1
fi

# Parses the output of lsblk to get the root partition number
# Example output:
# NAME        MOUNTPOINT
# nvme0n1
# ├─nvme0n1p1 /boot
# └─nvme0n1p3 /
# nvme1n1     /data
#
# Resulting in:
# └─nvme0n1p3 / -> nvme0n1p3 -> 3
ROOT_PARTITION_NUMBER=$(lsblk -no NAME,MOUNTPOINT | grep ' /$' | awk '{print $1;}' | sed 's/.*nvme[0-9]n[0-9]p//g')

if ! [[ "$ROOT_PARTITION_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "Error: ROOT_PARTITION_NUMBER is not a valid number: $ROOT_PARTITION_NUMBER"
  exit 1
fi

if [ -b /dev/nvme1n1 ] ; then
    if [[ "${VOLUME_TYPE}" == "data" ]]; then
        resize2fs /dev/nvme1n1

    elif [[ "${VOLUME_TYPE}" == "root" ]] ; then
        PLACEHOLDER_FL=/home/ubuntu/50M_PLACEHOLDER
        rm -f "${PLACEHOLDER_FL}" || true
        growpart /dev/nvme0n1 "${ROOT_PARTITION_NUMBER}"
        resize2fs "/dev/nvme0n1p${ROOT_PARTITION_NUMBER}"
        if [[ ! -f "${PLACEHOLDER_FL}" ]] ; then
            fallocate -l50M "${PLACEHOLDER_FL}"
        fi
    else
        echo "Invalid disk specified: ${VOLUME_TYPE}"
        exit 1
    fi
else
    growpart /dev/nvme0n1 "${ROOT_PARTITION_NUMBER}"
    resize2fs "/dev/nvme0n1p${ROOT_PARTITION_NUMBER}"
fi
echo "Done resizing disk"
