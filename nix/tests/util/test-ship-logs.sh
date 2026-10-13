#!/usr/bin/env bash
set -euo pipefail

common_sh=${1:-$(dirname "$0")/../../../ansible/files/admin_api_scripts/pg_upgrade_scripts/common.sh}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cat >"$tmp/curl" <<'SH'
#!/usr/bin/env bash
cat >"$CAPTURE"
SH
chmod +x "$tmp/curl"

head -c 1048576 /dev/zero | tr '\0' x >"$tmp/big.log"

export PATH="$tmp:$PATH" CAPTURE="$tmp/body.json"
# shellcheck disable=SC1090
source "$common_sh"

export REPORTING_ANON_KEY=k
export REPORTING_PROJECT_REF=ref
ship_logs "$tmp/big.log"

[ "$(jq -r '.content | length' "$CAPTURE")" -eq 1048576 ]
echo "ok"
