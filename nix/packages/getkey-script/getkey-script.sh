#!/usr/bin/env bash

set -euo pipefail

TMPDIR_BASE=$(mktemp -d)

KEY_DIR="${PGSODIUM_KEY_DIR:-$TMPDIR_BASE/pgsodium}"
KEY_FILE="$KEY_DIR/pgsodium.key"

# shellcheck disable=SC2174
if ! mkdir -p -m 1777 "$KEY_DIR" 2>/dev/null; then
	echo "Error: Could not create key directory $KEY_DIR" >&2
	exit 1
fi

if [[ ! -f $KEY_FILE ]]; then
	umask 022
	head -c 32 /dev/urandom | od -A n -t x1 | tr -d ' \n' >"$KEY_FILE"
fi

if [[ -f $KEY_FILE && -r $KEY_FILE ]]; then
	cat "$KEY_FILE"
else
	echo "Error: Cannot read key file $KEY_FILE" >&2
	exit 1
fi
