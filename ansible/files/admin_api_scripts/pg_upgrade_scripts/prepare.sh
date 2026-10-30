#! /usr/bin/env bash

# This script is runs in advance of the database version upgrade, on the newly
# launched instance which will eventually be promoted to become the primary
# database instance once the upgrade successfully completes, terminating the
# previous (source) instance.  The following commands safely stop the Postgres
# service and unmount the data disk off the newly launched instance, to be
# re-attached to the source instance and run the upgrade there.

## Code hardened see
## https://linear.app/supabase/issue/MPG-1283/harden-a-bit-preparesh

set -Eeuo pipefail

SCRIPT_DIR=$(dirname -- "$0")

# Define the log file BEFORE anything else and create it now,
# so it exists even if a later step (including sourcing common.sh) fails.
LOG_FILE="/var/log/pg-upgrade-prepare.log"
touch "$LOG_FILE"
chmod 640 "$LOG_FILE"

# From here on, everything written to stdout/stderr (log messages, but also
# errors from systemctl, install, sync, etc.) is appended to the log file.
exec >>"$LOG_FILE" 2>&1

# Source the shared helpers (log and ship_logs functions). If this fails,
# "log" is not available yet, so we write a timestamped message by hand
# before exiting.
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh" || {
  echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') cannot source $SCRIPT_DIR/common.sh"
  exit 1
}

# ship_logs reads these variables, and "set -u" would abort the script on an
# unset variable. Default them to empty (existing values are kept) so that
# ship_logs can handle the "no reporting key" case itself.
: "${REPORTING_ANON_KEY:=}"
: "${REPORTING_PROJECT_REF:=}"

# Log any unexpected failure (set -e) with the line number and failing command,
# so that no error can end the script silently.
trap 'log "prepare.sh FAILED at line $LINENO: \"$BASH_COMMAND\" (exit code $?)"' ERR

# Runs on every exit (success, explicit "exit 1" or set -e failure).
# It uploads the log file, but never changes the script's exit code and never
# lets an upload failure turn into a script failure.
on_exit() {
  local rc=$?
  trap - EXIT ERR   # avoid re-entering the traps from inside this handler
  # uploading the log in REPORTING_PROJECT_REF (see common.sh)
  ship_logs "$LOG_FILE" || log "Log upload failed (non-blocking)."
  exit "$rc"
}
trap on_exit EXIT

# starting log
log "prepare.sh started."

# check that /data is actually mounted
mountpoint -q /data || { log "/data is not mounted"; exit 1; }

# stop postgresql: "systemctl stop blocks until the unit has fully stopped"
# https://linear.app/supabase/issue/MPG-1283/harden-a-bit-preparesh#comment-cea7446f
# so there is no need to check pg_isready afterwards...
systemctl stop postgresql

# ...but let's still verify that the service is explicitly stopped
if systemctl is-active --quiet postgresql; then
  log "postgresql service is still active!"; exit 1
fi

# ...and that there are no remaining postgres processes
if pgrep -x postgres >/dev/null; then
  log "postgres processes are still alive!"; exit 1
fi

# copy the pgsodium root key with proper owner and permissions
install -m 600 -o postgres -g postgres \
  /etc/postgresql-custom/pgsodium_root.key /data/pgsodium_root.key

# flush cached writes to persistent storage
sync

# Unmount /data. Capture the native umount error message and route it through
# "log" so that it is timestamped like the rest of the log entries.
if ! umount_out=$(umount /data 2>&1); then
  log "Unable to unmount /data: $umount_out"
  # List the processes still using /data ("|| true" so a fuser failure
  # does not trigger the ERR trap and mask the real cause)
  log "Processes using /data:"
  log "$(fuser -vm /data 2>&1 || true)"
  exit 1
fi

# final log if everything went well
# (we don't get here unless there were no previous errors)
log "prepare.sh ended with no errors."
# ship_logs is then called automatically by the EXIT trap (on_exit)
