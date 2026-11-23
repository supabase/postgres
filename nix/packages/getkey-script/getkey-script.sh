#!/usr/bin/env bash

set -euo pipefail

TMPDIR_BASE=$(mktemp -d)

KEY_DIR="${PGSODIUM_KEY_DIR:-$TMPDIR_BASE/pgsodium}"
KEY_FILE="$KEY_DIR/pgsodium.key"

if ! mkdir -p "$KEY_DIR" 2>/dev/null; then
	echo "Error: Could not create key directory $KEY_DIR" >&2
	exit 1
fi
chmod 1777 "$KEY_DIR"

if [[ ! -f $KEY_FILE ]]; then
	if ! (dd if=/dev/urandom bs=32 count=1 2>/dev/null | od -A n -t x1 | tr -d ' \n' >"$KEY_FILE"); then
		if ! (openssl rand -hex 32 >"$KEY_FILE"); then
			echo "00000000000000000000000000000000" >"$KEY_FILE"
			echo "Warning: Using fallback key" >&2
		fi
	fi
	chmod 644 "$KEY_FILE"
fi

if [[ -f $KEY_FILE && -r $KEY_FILE ]]; then
	cat "$KEY_FILE"
else
	echo "Error: Cannot read key file $KEY_FILE" >&2
	exit 1
fi
