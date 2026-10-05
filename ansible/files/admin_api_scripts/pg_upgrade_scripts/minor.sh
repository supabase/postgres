#! /usr/bin/env bash

## Upgrades Postgres in place to another minor of the same major: switches the
## postgres profile to a postgres-env store path and restarts. Rolls back to the
## previous profile generation if the restart or the checks fail.

set -eEuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=/dev/null
source "${PG_UPGRADE_COMMON:-$SCRIPT_DIR/common.sh}"

TARGET=${1:?Usage: $0 <postgres-env store path>}
PROFILE=${POSTGRES_PROFILE:-/nix/var/nix/profiles/per-user/postgres/profile}
CONFIG_DIR=${POSTGRES_CONFIG_DIR:-/etc/postgresql}
PGBOUNCER_ADMIN=${PGBOUNCER_ADMIN:-}

NIX_DAEMON_PROFILE=/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
if [ -f "$NIX_DAEMON_PROFILE" ]; then
	# shellcheck disable=SC1090
	source "$NIX_DAEMON_PROFILE"
fi
export PATH="$PATH:/usr/lib/postgresql/bin"

flipped=false
paused=false

function pgbouncer_admin {
	timeout 30 psql "$PGBOUNCER_ADMIN" -X -q -c "$1"
}

function wait_for_postgres {
	retry 8 pg_isready -h localhost -q
}

function cleanup {
	trap - ERR
	set +e
	if [ "$flipped" = true ]; then
		log "Rolling back $PROFILE to the previous generation"
		nix-env -p "$PROFILE" --rollback
		systemctl restart postgresql
		wait_for_postgres
	fi
	if [ "$paused" = true ]; then
		pgbouncer_admin RESUME
	fi
	log "Minor upgrade to $TARGET failed"
	exit 1
}

trap cleanup ERR

if [ "$(readlink -f "$PROFILE")" = "$TARGET" ]; then
	log "$PROFILE already points at $TARGET"
	exit 0
fi

check_free_space $((2 * 1024 * 1024))
retry 3 timeout -k 10s 120s nix-store -r "$TARGET" >/dev/null

target_version=$("$TARGET/bin/postgres" --version | awk '{print $NF}')
running_version=$(run_sql -tAXc "show server_version")
if [ "${target_version%%.*}" != "${running_version%%.*}" ]; then
	log "ERROR: $TARGET has $target_version but $running_version is running; only minor upgrades are supported"
	exit 1
fi

setpriv --reuid=postgres --regid=postgres --init-groups "$TARGET/bin/postgres" -C server_version -D "$CONFIG_DIR" >/dev/null
identity=$(run_sql -tAXc "select system_identifier from pg_control_system()")

if [ -n "$PGBOUNCER_ADMIN" ] && systemctl is-active --quiet pgbouncer; then
	paused=true
	pgbouncer_admin PAUSE
fi

run_sql -XqAc "checkpoint"
log "Switching $PROFILE from $running_version to $target_version"
nix-env -p "$PROFILE" --set "$TARGET"
flipped=true
systemctl restart postgresql
wait_for_postgres

if [ "$(run_sql -tAXc "show server_version")" != "$target_version" ]; then
	log "ERROR: server did not come back on $target_version"
	false
fi
if [ "$(run_sql -tAXc "select system_identifier from pg_control_system()")" != "$identity" ]; then
	log "ERROR: system identifier changed"
	false
fi
flipped=false

if [ "$paused" = true ]; then
	pgbouncer_admin RESUME
	paused=false
fi
log "Upgraded to $target_version"
