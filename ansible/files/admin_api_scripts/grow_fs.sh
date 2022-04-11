#! /usr/bin/env bash

set -euo pipefail

growpart /dev/nvme0n1 2
resize2fs /dev/nvme0n1p2

echo "Done resizing disk"
