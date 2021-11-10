#! /usr/bin/env bash

set -euo pipefail

growpart /dev/nvme0n1 1
resize2fs /dev/nvme0n1p1

echo "Done resizing disk"
