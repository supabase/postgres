#!/usr/bin/env bash
# Fails if any file in ./result requires a glibc symbol version above MAX_ALLOWED.
set -Eeu -o pipefail

MAX_ALLOWED="2.31"

HIT=$(find -L result -type f -exec sh -c \
	'objdump -T "$1" 2>/dev/null | grep -oE "GLIBC_[0-9.]+" | sed -E "s#GLIBC_([0-9.]+)#\1 $1#"' _ {} \; |
	sort -V | tail -1)

if [ -z "$HIT" ]; then
	exit 0
fi

FLOOR=${HIT%% *}
echo "glibc floor: $FLOOR (max allowed: $MAX_ALLOWED)"
if [ "$(printf '%s\n%s' "$MAX_ALLOWED" "$FLOOR" | sort -V | tail -1)" != "$MAX_ALLOWED" ]; then
	echo "::error::glibc floor $HIT exceeds max allowed $MAX_ALLOWED in ${1:-result}"
	exit 1
fi
