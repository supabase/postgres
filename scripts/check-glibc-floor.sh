#!/usr/bin/env bash
# Fails if any file in ./result requires a glibc symbol version above MAX_ALLOWED.
set -Eeu -o pipefail

MAX_ALLOWED="2.31"

FLOOR=$(find -L result -type f -exec objdump -T {} \; 2>/dev/null \
  | grep -oE 'GLIBC_[0-9.]+' | sed 's/GLIBC_//' | sort -V | tail -1)

if [ -z "$FLOOR" ]; then
  exit 0
fi

echo "glibc floor: $FLOOR (max allowed: $MAX_ALLOWED)"
if [ "$(printf '%s\n%s' "$MAX_ALLOWED" "$FLOOR" | sort -V | tail -1)" != "$MAX_ALLOWED" ]; then
  echo "::error::glibc floor $FLOOR exceeds max allowed $MAX_ALLOWED in ${1:-result}"
  exit 1
fi
