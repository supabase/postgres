#! /usr/bin/env bash

set -euo pipefail

resize2fs /dev/nvme1n1

echo "Done resizing disk"
