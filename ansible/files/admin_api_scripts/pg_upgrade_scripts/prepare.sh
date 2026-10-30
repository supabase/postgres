#! /usr/bin/env bash

# This script is runs in advance of the database version upgrade, on the newly
# launched instance which will eventually be promoted to become the primary
# database instance once the upgrade successfully completes, terminating the
# previous (source) instance.  The following commands safely stop the Postgres
# service and unmount the data disk off the newly launched instance, to be
# re-attached to the source instance and run the upgrade there.

## Code hardened see
## https://linear.app/supabase/issue/MPG-1283/harden-a-bit-preparesh

#! /usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(dirname -- "$0")

# The log file is never truncated: when the script is retried by the caller,
# each attempt appends to the same file. It is created right away so that it
# exists even if a later step fails.
LOG_FILE="/var/log/pg-upgrade-prepare.log"
touch "$LOG_FILE"
chmod 640 "$LOG_FILE"

# Detect a retry BEFORE writing anything: if "started" is already in the
# file, a previous attempt has run and failed.
RETRY=0
if grep -qF "prepare.sh started" "$LOG_FILE"; then
  RETRY=1
fi

# From here on, everything written to stdout/stderr (log messages, but also
# errors from systemctl, install, sync, etc.) is appended to the log file.
exec >>"$LOG_FILE" 2>&1

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

# ship_logs reads these variables, and "set -u" would abort the script on an
# unset variable. Default them to empty (existing values are kept) so that
# ship_logs can handle the "no reporting key" case itself.
: "${REPORTING_ANON_KEY:=}"
: "${REPORTING_PROJECT_REF:=}"

# Runs on every exit (success, explicit "exit 1" or set -e failure).
#   - success: final message + single upload of the log file
#   - failure: nothing more is written (the error is already in the log) and
#     nothing is uploaded: the script cannot know whether the caller will
#     retry, so the caller handles the "gave up" case.
# The script's exit code is always preserved for the caller.
on_exit() {
  local rc=$?
  trap - EXIT ERR   # avoid re-entering the traps from inside this handler

  if [ "$rc" -eq 0 ]; then
    if [ "$RETRY" -eq 0 ]; then
      log "prepare.sh ended with no errors."
    else
      log "prepare.sh finally ended without error this time."
    fi
    # Single upload of the log file; never fatal
    if declare -F ship_logs >/dev/null; then
      ship_logs "$LOG_FILE" || log "Log upload failed (non-blocking)."
    else
      log "ship_logs is not available, log upload skipped."
    fi
  fi
  exit "$rc"
}
trap on_exit EXIT

# Written at every attempt. It is also the marker used above to detect
# retries, so do not change its wording.
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

# Reaching this point means success: the final message and the log upload
# are handled by the EXIT trap (on_exit).
