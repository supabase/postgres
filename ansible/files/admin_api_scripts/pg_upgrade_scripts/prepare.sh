#! /usr/bin/env bash

# This script runs in advance of the database version upgrade, on the newly
# launched instance which will eventually be promoted to become the primary
# database instance once the upgrade successfully completes, terminating the
# previous (source) instance.  The following commands safely stop the Postgres
# service and unmount the data disk off the newly launched instance, to be
# re-attached to the source instance and run the upgrade there.

set -Eeuo pipefail

SCRIPT_DIR=$(dirname -- "$0")

# Each attempt overwrites the log. Failed attempts are shipped before the retry.
LOG_FILE="/var/log/pg-upgrade-prepare.log"
touch "$LOG_FILE"
chmod 644 "$LOG_FILE"

# From here on, everything written to stdout/stderr (log messages, but also
# errors from systemctl, install, sync, etc.) is written to the log file.
exec >"$LOG_FILE" 2>&1

# Minimal fallback so that "log" exists even if common.sh cannot be sourced.
# common.sh redefines it with the real implementation.
log() { echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') $*"; }

# Log any unexpected failure (set -e) with the line number and failing command,
# so that no error can end the script silently.
trap 'log "prepare.sh FAILED at line $LINENO: \"$BASH_COMMAND\" (exit code $?)"' ERR

# Source the shared helpers (log and ship_logs functions)
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh" || {
	log "cannot source $SCRIPT_DIR/common.sh"
	exit 1
}

on_exit() {
	local rc=$?
	trap - EXIT ERR

	# ship the log

	if [ "$rc" -eq 0 ]; then
		log "prepare.sh ended with no errors"
		ship_logs "$LOG_FILE" || log "Log upload failed (non-blocking)."
	else
		log "prepare.sh ended with errors"
		ship_logs "$LOG_FILE" || log "Log upload failed (non-blocking)."
	fi
	exit "$rc"
}
trap on_exit EXIT

log "prepare.sh started"

# check that /data is actually mounted
mountpoint -q /data || {
	log "/data is not mounted"
	exit 1
}

# stop postgresql: "systemctl stop blocks until the unit has fully stopped"
# so there is no need to check pg_isready afterwards...
systemctl stop postgresql

# ...but let's still verify that the service is explicitly stopped
if systemctl is-active --quiet postgresql; then
	log "postgresql service is still active!"
	exit 1
fi

# ...and that there are no remaining postgres processes
if pgrep -x postgres >/dev/null; then
	log "postgres processes are still alive!"
	exit 1
fi

# copy the pgsodium root key with proper owner and permissions
# (optional: initiate.sh also treats it as optional)
if [ -f /etc/postgresql-custom/pgsodium_root.key ]; then
	install -m 600 -o postgres -g postgres \
		/etc/postgresql-custom/pgsodium_root.key /data/pgsodium_root.key
else
	log "WARNING: /etc/postgresql-custom/pgsodium_root.key not found; not copying it"
fi

# copy the anon key used to ship logs to the error_logs project
# (optional: without it logs are simply not shipped, which must not block the upgrade)
if [ -f /root/upgrade-reporting-credentials ]; then
	install -m 600 -o root -g root \
		/root/upgrade-reporting-credentials /data/upgrade-reporting-credentials.target
else
	log "WARNING: /root/upgrade-reporting-credentials not found; not copying it (logs will not be shipped)"
fi

# flush cached writes to persistent storage
sync

# Unmount /data. Capture the native umount error message and route it through
# "log" so that it is timestamped like the rest of the log entries.
if ! umount_out=$(umount /data 2>&1); then
	log "Unable to unmount /data: $umount_out"
	# List the processes whose cwd is under /data.
	log "Processes using /data:"

	# Processes with open files (or any other use) on /data, not only those whose
	# cwd is there. Best effort: the tools may be absent, never fail because of it.
	if command -v fuser >/dev/null 2>&1; then
		log "fuser -vm /data:"
		fuser -vm /data 2>&1 || true
	elif command -v lsof >/dev/null 2>&1; then
		log "lsof +f -- /data:"
		lsof +f -- /data 2>&1 || true
	else
		log "neither fuser nor lsof available; listing cwd only"
	fi

	# nullglob: with no match, the /proc/[0-9]*/cwd pattern expands to nothing
	# instead of being passed literally to stat
	shopt -s nullglob

	QUOTING_STYLE=literal stat -c '%U %N' /proc/[0-9]*/cwd 2>/dev/null |
		sed -nE 's|^(\S+) /proc/([0-9]+)/cwd -> /data(/.*)?$|\1 \2|p' |
		while read -r user pid; do
			comm=$(cat "/proc/$pid/comm" 2>/dev/null) || continue
			log "user: ${user} pid: ${pid} command: ${comm}"
		done || true

	exit 1
fi

# Reaching this point means success: the final message and the log upload
# are handled by the EXIT trap (on_exit).
