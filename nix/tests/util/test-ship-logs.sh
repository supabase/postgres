#!/usr/bin/env bash
set -euo pipefail

common_sh=${1:-$(dirname "$0")/../../../ansible/files/admin_api_scripts/pg_upgrade_scripts/common.sh}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

printf '#!%s\ncat >"%s"\n' "$(command -v bash)" "$tmp/body.json" >"$tmp/curl"
chmod +x "$tmp/curl"

head -c 1048576 /dev/zero | tr '\0' x >"$tmp/big.log"

export PATH="$tmp:$PATH"
# shellcheck disable=SC1090
source "$common_sh"

export REPORTING_ANON_KEY=k
export REPORTING_PROJECT_REF=ref
ship_logs "$tmp/big.log"

[ "$(jq -r '.content | length' "$tmp/body.json")" -eq 1048576 ]
