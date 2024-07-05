#! /usr/bin/env bash

set -euo pipefail

VOLUME_TYPE=${1:-data}

if [ -b /dev/nvme1n1 ] ; then
    if [[ "${VOLUME_TYPE}" == "data" ]]; then
        resize2fs /dev/nvme1n1

    elif [[ "${VOLUME_TYPE}" == "root" ]] ; then
        PLACEHOLDER_FL=/home/ubuntu/50M_PLACEHOLDER
        rm -f "${PLACEHOLDER_FL}" || true
        growpart /dev/nvme0n1 2
        resize2fs /dev/nvme0n1p2
        if [[ ! -f "${PLACEHOLDER_FL}" ]] ; then
            fallocate -l50M "${PLACEHOLDER_FL}"
        fi
    else
        echo "Invalid disk specified: ${VOLUME_TYPE}"
        exit 1
    fi
else
    growpart /dev/nvme0n1 2
    resize2fs /dev/nvme0n1p2
fi
echo "Done resizing disk"
