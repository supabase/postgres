#! /usr/bin/env bash

# Start guard for initiate.sh: keeps the source Postgres down during the pg_upgrade
# file copy. Sourced by initiate.sh and tests/pg_upgrade/test-start-guard.sh.
# Expects log, IS_CI, PGDATAOLD and PGDATANEW from the caller.

# From step 10 until cleanup, nothing may start the source postgres: pg_upgrade
# copies the data files without a postmaster holding the directory, and a start
# in that window (Salt's `service.running`, adminapi, Restart=always, ...)
# yields a copy that is inconsistent with the dump. Two independent guards:
#  1. a runtime systemd drop-in that makes `systemctl start` fail while this
#     script or pg_upgrade is alive (a SIGKILLed script must not leave the
#     source blocked until a reboot);
#  2. a postmaster.pid in the old data dir holding pg_upgrade's own PID, which
#     makes any postmaster (systemd or direct pg_ctl) refuse to start while
#     pg_upgrade lives. The file goes stale when pg_upgrade exits.
PG_UPGRADE_LOCK_DROPIN_DIR="/run/systemd/system/postgresql.service.d"
PG_UPGRADE_LOCK_DROPIN="$PG_UPGRADE_LOCK_DROPIN_DIR/pg-upgrade-lock.conf"
PG_UPGRADE_PID_LOCK_MARKER="/run/pg-upgrade-source.pid"
PG_UPGRADE_PID_LOCK_TMP_NAME="postmaster.pid.pg-upgrade-lock"
PG_UPGRADE_INITIATE_PID_FILE="/run/pg-upgrade-initiate.pid"
PG_UPGRADE_START_GUARD="/run/pg-upgrade-start-guard.sh"
PG_UPGRADE_LOCK_WATCHER_PID=""
PG_UPGRADE_START_BLOCKED=""

block_postgres_start() {
	# systemd needs absolute paths, and a drop-in naming a missing binary would
	# silently never expire: fail here instead.
	local sh_path rm_path systemctl_path
	sh_path=$(type -P sh) || {
		log "ERROR: sh not found in PATH"
		return 1
	}
	rm_path=$(type -P rm) || {
		log "ERROR: rm not found in PATH"
		return 1
	}
	systemctl_path=$(type -P systemctl) || {
		log "ERROR: systemctl not found in PATH"
		return 1
	}
	mkdir -p "$PG_UPGRADE_LOCK_DROPIN_DIR"
	# initiate_upgrade runs in a background subshell: $BASHPID is its own pid, $$ is
	# the already exited parent.
	printf '%s\n' "${BASHPID:-$$}" >"$PG_UPGRADE_INITIATE_PID_FILE"
	# Refuse a start only while the pid in one of the files is alive, so a SIGKILLed
	# script stops blocking once pg_upgrade is gone too. Run through sh by the
	# drop-in because /run is mounted noexec.
	cat >"$PG_UPGRADE_START_GUARD" <<'GUARD'
for pid_file in "$@"; do
	pid=$(cat "$pid_file" 2>/dev/null) || continue
	# not a number: some shells' kill treat it as a job name, not an error
	case "$pid" in
	'' | *[!0-9]*) continue ;;
	esac
	if kill -0 "$pid" 2>/dev/null; then
		exit 255
	fi
done
exit 0
GUARD
	# ExecCondition runs before the unit's own ExecStartPre (postgres_prestart.sh,
	# as root), which therefore does not run for a refused start. Exit 255 fails the
	# start, 1-254 would only skip it silently. The unit does not run as root, so
	# `+` is needed to see root-owned pids and to remove files under /run. A start
	# that gets past the guard means this script and pg_upgrade are gone: the
	# ExecStartPost lines then remove the drop-in so Restart=no does not outlive it.
	printf '[Service]\nExecCondition=+%s %s %s %s\n' \
		"$sh_path" "$PG_UPGRADE_START_GUARD" "$PG_UPGRADE_INITIATE_PID_FILE" "$PG_UPGRADE_PID_LOCK_MARKER" >"$PG_UPGRADE_LOCK_DROPIN"
	printf 'ExecStartPost=-+%s -f %s %s %s %s\nExecStartPost=-+%s daemon-reload\nRestart=no\n' \
		"$rm_path" "$PG_UPGRADE_LOCK_DROPIN" "$PG_UPGRADE_INITIATE_PID_FILE" "$PG_UPGRADE_PID_LOCK_MARKER" "$PG_UPGRADE_START_GUARD" \
		"$systemctl_path" >>"$PG_UPGRADE_LOCK_DROPIN"
	PG_UPGRADE_START_BLOCKED=1
	systemctl daemon-reload
}

# Wait for the new cluster's temp server (the old one is down from then on,
# its schema dump is done) and then claim the old data dir's postmaster.pid.
# It must not exist before: pg_upgrade aborts if it finds one at startup, so
# finding one now means a postmaster started during the copy.
# The watcher exits 0 when it took the lock or when there is nothing left to
# lock (initiate.sh and pg_upgrade are gone), and non-zero when it could not
# take the lock: assert_source_stayed_down turns that into a failed upgrade.
start_pid_lock_watcher() {
	local initiate_pid=${BASHPID:-$$}
	(
		# set -E would otherwise run cleanup() from this subshell
		trap - ERR EXIT
		set +e
		until [ -e "$PGDATANEW/postmaster.pid" ]; do
			# initiate.sh SIGKILLed and pg_upgrade gone: nothing left to lock
			if ! kill -0 "$initiate_pid" 2>/dev/null && ! pgrep -u postgres -f -- "--old-datadir=${PGDATAOLD}" >/dev/null; then
				exit 0
			fi
			sleep 0.2
		done
		upg_pid=$(pgrep -u postgres -f -- "--old-datadir=${PGDATAOLD}" | head -1)
		if [ -z "$upg_pid" ]; then
			log "WARNING: pg_upgrade not found; not creating the pg_upgrade lock"
			exit 1
		fi
		if [ -e "$PGDATAOLD/postmaster.pid" ]; then
			log "ERROR: $PGDATAOLD/postmaster.pid already exists; a postmaster ran during the copy"
			exit 1
		fi
		printf '%s\n' "$upg_pid" >"$PG_UPGRADE_PID_LOCK_MARKER" || exit 1
		# Build the file aside and link it into place: the link is atomic and fails
		# if the name exists, so a watcher killed by unblock_postgres_start can never
		# leave a truncated postmaster.pid behind (cmp would not match it).
		lock_tmp="$PGDATAOLD/$PG_UPGRADE_PID_LOCK_TMP_NAME"
		if ! {
			cat "$PG_UPGRADE_PID_LOCK_MARKER" >"$lock_tmp" &&
				chown postgres:postgres "$lock_tmp" &&
				chmod 0600 "$lock_tmp" &&
				ln "$lock_tmp" "$PGDATAOLD/postmaster.pid"
		}; then
			rm -f "$lock_tmp"
			log "ERROR: could not create the pg_upgrade PID lock"
			exit 1
		fi
		rm -f "$lock_tmp"
		log "Locked $PGDATAOLD with pg_upgrade pid $upg_pid"
	) &
	PG_UPGRADE_LOCK_WATCHER_PID=$!
}

# Idempotent: cleanup() can run before step 10 or more than once.
unblock_postgres_start() {
	if [ -n "$PG_UPGRADE_LOCK_WATCHER_PID" ]; then
		kill "$PG_UPGRADE_LOCK_WATCHER_PID" 2>/dev/null || true
		wait "$PG_UPGRADE_LOCK_WATCHER_PID" 2>/dev/null || true
		PG_UPGRADE_LOCK_WATCHER_PID=""
	fi
	local pidfile="${PGDATAOLD:-/nonexistent}/postmaster.pid"
	# a watcher killed between writing and linking leaves only this temp file
	rm -f "${PGDATAOLD:-/nonexistent}/$PG_UPGRADE_PID_LOCK_TMP_NAME"
	# Callers run this under `||` where set -e is off, so report failures through
	# the return status: a failed daemon-reload leaves the block loaded in systemd.
	local rc=0
	if [ -f "$PG_UPGRADE_PID_LOCK_MARKER" ]; then
		if [ -f "$pidfile" ] && cmp -s "$PG_UPGRADE_PID_LOCK_MARKER" "$pidfile"; then
			rm -f "$pidfile" || rc=1
		fi
		if [ "$rc" -eq 0 ]; then
			rm -f "$PG_UPGRADE_PID_LOCK_MARKER" || rc=1
		fi
	fi
	if [ -z "$IS_CI" ]; then
		if [ -e "$PG_UPGRADE_LOCK_DROPIN" ]; then
			PG_UPGRADE_START_BLOCKED=1
			rm -f "$PG_UPGRADE_LOCK_DROPIN" || rc=1
			rm -f "$PG_UPGRADE_INITIATE_PID_FILE" || rc=1
			rmdir --ignore-fail-on-non-empty "$PG_UPGRADE_LOCK_DROPIN_DIR" || true
		fi
		systemctl daemon-reload || rc=1
		# Only after a successful reload: with the drop-in still loaded, a missing
		# guard exits 127, which systemd treats as a silent skip of the start.
		if [ "$rc" -eq 0 ]; then
			rm -f "$PG_UPGRADE_START_GUARD" || rc=1
		fi
		if [ "$rc" -eq 0 ] && [ -n "$PG_UPGRADE_START_BLOCKED" ]; then
			systemctl reset-failed postgresql || true
			PG_UPGRADE_START_BLOCKED=""
		fi
	fi
	return $rc
}

# The source must have stayed down for the whole copy; if not, the copy is
# inconsistent and the upgrade has to fail (the source data is untouched).
assert_source_stayed_down() {
	local state="" watcher_rc=0
	# A watcher that is still polling is fine; one that is gone must have exited 0.
	# `wait` reports a child's status only once, so nothing may wait on the watcher
	# before this check (unblock_postgres_start does, and runs after it). 127 means
	# the status is not available (already reaped), not that the watcher failed.
	if [ -n "$PG_UPGRADE_LOCK_WATCHER_PID" ] && ! kill -0 "$PG_UPGRADE_LOCK_WATCHER_PID" 2>/dev/null; then
		wait "$PG_UPGRADE_LOCK_WATCHER_PID" || watcher_rc=$?
		if [ "$watcher_rc" -ne 0 ] && [ "$watcher_rc" -ne 127 ]; then
			log "ERROR: the pg_upgrade lock could not be taken; the copied data files may be inconsistent"
			return 1
		fi
	fi
	if [ -z "$IS_CI" ]; then
		state=$(systemctl is-active postgresql || true)
	fi
	if [ "$state" = "active" ] || [ "$state" = "activating" ] || [ "$state" = "reloading" ]; then
		log "ERROR: postgresql.service is ${state} after pg_upgrade; the copied data files may be inconsistent"
		return 1
	fi
	if [ -f "$PGDATAOLD/postmaster.pid" ] && ! cmp -s "$PG_UPGRADE_PID_LOCK_MARKER" "$PGDATAOLD/postmaster.pid"; then
		log "ERROR: a postmaster ran in $PGDATAOLD during pg_upgrade; the copied data files may be inconsistent"
		return 1
	fi
}
