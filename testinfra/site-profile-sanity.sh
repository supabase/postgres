#!/usr/bin/env bash
# Usage: site-profile-sanity <updated|rolled-back>
# PG_RESTART and PSQL override the AMI defaults.
set -euo pipefail

MODE="${1:?Usage: $0 <updated|rolled-back>}"
read -ra PG_RESTART <<<"${PG_RESTART:-systemctl restart postgresql}"
read -ra PSQL <<<"${PSQL:-sudo -u postgres psql -X -At -c}"

"${PG_RESTART[@]}"

[[ "$("${PSQL[@]}" 'select 1')" == 1 ]]

if [[ $MODE == updated ]]; then
	"${PSQL[@]}" "load 'supautils'"
	"${PSQL[@]}" 'show dynamic_library_path' | grep -q /nix/var/nix/profiles/site/lib/postgresql
fi

echo "ok: sanity $MODE"
