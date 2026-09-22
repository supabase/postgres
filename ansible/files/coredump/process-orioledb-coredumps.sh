#!/bin/bash
# Process PostgreSQL/OrioleDB core dumps captured by systemd-coredump into a
# text summary.
#
# Key ideas:
#  - Only cores of the postgres binary are processed; any other core left
#    untouched
#  - No environment variables are ever collected. The GDB extraction (see
#    cmds.gdb, matching OrioleDB's own CI debugging script) does run
#    `thread apply all bt full`, which prints local variable values and can
#    surface fragments of in-memory data (buffer/tuple pointers etc.) - this
#    is a deliberate, reviewed trade-off in favor of debuggability, not an
#    oversight.
#  - Cores are deleted after a successful run or quarantined (metadata only)
#    after MAX_ATTEMPTS failures.

set -euo pipefail

STATE_DIR=/var/lib/orioledb-coredumps/state
OUTPUT_DIR=/var/lib/orioledb-coredumps/diagnostics
QUARANTINE_DIR=/var/lib/orioledb-coredumps/quarantine
LOCK_FILE=/run/orioledb-coredump.lock

MAX_ATTEMPTS=3
EXTRACTION_TIMEOUT=120
MAX_AGE_DAYS=7
MAX_TOTAL_BYTES=$((5 * 1024 * 1024 * 1024)) # independent of systemd-coredump's own MaxUse

GDB_DEBUG_DIR=/var/lib/postgresql/.nix-profile/lib/debug
GDB_CMDS_FILE=/usr/local/sbin/orioledb-coredump-cmds.gdb
PGDATA_CURRENT_LOGFILES=/var/lib/postgresql/data/current_logfiles

log() {
	echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] $*"
}

# /usr/lib/postgresql/bin/postgres is a Nix wrapper *script* (sets
# NIX_PGLIBDIR, then execs the real ELF at .../bin/.postgres-wrapped) - not
# an executable itself. A crashing backend's real, kernel-recorded
# Executable: is that wrapped path (basename ".postgres-wrapped"), never the
# wrapper. Normalize both forms to "postgres" for comparison, and always use
# the per-crash Executable: path (not a hardcoded one) for readelf/gdb.
normalize_exe_basename() {
	local base
	base=$(basename "$1")
	base="${base#.}"
	base="${base%-wrapped}"
	printf '%s' "$base"
}

# orioledb.so has no fixed, predictable path either - there is no
# /usr/lib/postgresql/lib mirror of it. It lives in the same nix store
# derivation as the resolved postgres executable, just under lib/ instead
# of bin/, e.g. .../postgresql-and-plugins-17_20/{bin/.postgres-wrapped,
# lib/orioledb.so} - so derive it from $exe rather than guessing a path.
orioledb_lib_path() {
	local exe_dir
	exe_dir=$(dirname "$(dirname "$1")")
	printf '%s/lib/orioledb.so' "$exe_dir"
}

# coredumpctl on this systemd version (255.4) has no "rm"/"delete" verb - the
# only reliable way to remove a core is to delete its on-disk Storage: path
# directly. Returns success only if the path is actually gone afterward.
delete_core() {
	local path="$1"
	[ -z "$path" ] && return 1
	rm -f -- "$path"
	[ ! -e "$path" ]
}

# The active postgresql log file has an unpredictable name and can be
# csvlog, stderr-text, or both depending on config (this AMI defaults to
# csvlog-only, e.g. /var/log/postgresql/postgresql.csv - the stderr-format
# postgresql.log stops receiving anything the moment the logging collector
# switches over at startup). PGDATA/current_logfiles is postgres's own,
# always-current record of the real path(s); prefer csvlog, fall back to
# stderr. Either format still starts each line with a literal timestamp, so
# the grep -F substring match below works unchanged either way.
current_postgres_log() {
	[ -f "$PGDATA_CURRENT_LOGFILES" ] || return 0
	awk '$1 == "csvlog" {p = $2} $1 == "stderr" && !p {p = $2} END {print p}' "$PGDATA_CURRENT_LOGFILES"
}

enforce_retention() {
	find "$OUTPUT_DIR" -maxdepth 1 -type f -mtime "+${MAX_AGE_DAYS}" -delete 2>/dev/null || true

	while true; do
		total=$(du -sb "$OUTPUT_DIR" 2>/dev/null | cut -f1)
		[ -z "$total" ] && break
		[ "$total" -le "$MAX_TOTAL_BYTES" ] && break
		oldest=$(find "$OUTPUT_DIR" -maxdepth 1 -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | head -1 | cut -d' ' -f2-)
		[ -z "$oldest" ] && break
		log "retention: removing oldest bundle $oldest to stay under ${MAX_TOTAL_BYTES} bytes"
		rm -f "$oldest"
	done
}

# Handles one candidate crash, given its PID: decide whether it's ours to
# process, extract a diagnostic bundle via GDB, then delete the raw core.
# (1) look up the crash via coredumpctl
# (2) decide keep/ignore/quarantine based on prior attempts
# (3) export the core and run GDB against it
# (4) write the bundle and delete the raw core. Returns 1 only for failures
#     worth retrying next run (main() logs those); every other outcome is
#     ignored, quarantined, or successfully processed - returns 0.
process_one() {
	local pid="$1"

	# coredumpctl matches reliably by PID; matching by the raw storage path
	# (which encodes an escaped comm, e.g. "core.\x2epostgres-wrapp....zst"
	# for the wrapped binary below) was found to fail in practice.
	local meta
	if ! meta=$(coredumpctl info "$pid" --no-pager 2>/dev/null); then
		log "pid ${pid}: coredumpctl info failed"
		return 1
	fi

	local exe boot_id storage_path
	exe=$(awk -F': ' '/^ *Executable:/ {print $2; exit}' <<<"$meta")
	boot_id=$(awk -F': ' '/^ *Boot ID:/ {print $2; exit}' <<<"$meta")
	# "Storage: /path/to/core (present)" -> "/path/to/core"
	storage_path=$(sed -n 's/^ *Storage: \(.*\) (.*)$/\1/p' <<<"$meta" | head -1)
	# PID alone isn't a safe dedup key long-term (PIDs get reused across
	# boots), so pair it with boot ID - matches "state keyed by boot ID plus
	# dump identifier" from the original design.
	local key="${boot_id}-${pid}"
	local state_file="${STATE_DIR}/${key}"

	# .done means "final decision made, never look at this dump again"
	# (processed successfully, ignored as non-postgres, or quarantined).
	# .attempts only counts *failed* tries, to cap retries before quarantine.
	[ -f "${state_file}.done" ] && return 0

	local attempts=0
	[ -f "${state_file}.attempts" ] && attempts=$(cat "${state_file}.attempts")
	if [ "$attempts" -ge "$MAX_ATTEMPTS" ]; then
		log "pid ${pid}: exceeded ${MAX_ATTEMPTS} attempts, discarding core (metadata kept in ${QUARANTINE_DIR})"
		echo "$meta" >"${QUARANTINE_DIR}/${key}.info"
		if delete_core "$storage_path"; then
			log "pid ${pid}: raw core deleted"
		else
			log "pid ${pid}: WARNING - could not delete raw core at '${storage_path}'"
		fi
		touch "${state_file}.done"
		return 0
	fi

	# /usr/lib/postgresql/bin/postgres is a wrapper script that execs the
	# real ELF at .../bin/.postgres-wrapped - the kernel (and therefore
	# coredumpctl's Executable:) always records the latter. Normalize both
	# forms before comparing, so we don't silently ignore every real crash.
	if [[ "$(normalize_exe_basename "$exe")" != "postgres" ]]; then
		log "pid ${pid}: executable '${exe}' is not postgres, ignoring"
		touch "${state_file}.done"
		return 0
	fi

	# From here on we're committed to actually processing this dump, so
	# count it as an attempt before doing any of the risky (slow, can fail)
	# work below - a crash/timeout past this point still gets retried, up
	# to MAX_ATTEMPTS
	echo $((attempts + 1)) >"${state_file}.attempts"

	# coredumpctl stores the core compressed; pull a private, working copy
	# out into a root-only scratch dir before handing it to GDB. The trap
	# guarantees that scratch dir is removed when this function returns, no
	# matter which of the several `return`s below fires.
	local tmpdir
	tmpdir=$(mktemp -d /tmp/coredump-XXXXXX)
	chmod 700 "$tmpdir"
	# suppress shellcheck warning about quoting $tmpdir in the trap command -
	# it's correct to quote it, and the trap is evaluated at runtime,
	# not parse time.
	# shellcheck disable=SC2064
	trap "rm -rf '$tmpdir'" RETURN

	if ! timeout "$EXTRACTION_TIMEOUT" coredumpctl dump "$pid" --output "${tmpdir}/core" >/dev/null 2>&1; then
		log "pid ${pid}: export failed or timed out"
		return 1
	fi

	# Already have this in $meta from the coredumpctl info call above -
	# just pulling out the two fields the bundle header needs.
	local signal timestamp
	signal=$(awk -F': ' '/^ *Signal:/ {print $2; exit}' <<<"$meta")
	timestamp=$(awk -F': ' '/^ *Timestamp:/ {print $2; exit}' <<<"$meta")

	# Everything from here to the closing "}" is the diagnostic bundle
	# itself, one section at a time, redirected straight to $bundle -
	# there's no in-memory buffering of it, so a slow/hanging step just
	# shows up as a truncated file rather than blocking the whole write.
	local bundle="${OUTPUT_DIR}/${key}.txt"
	{
		echo "== OrioleDB/PostgreSQL coredump diagnostic bundle =="
		echo "generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
		echo "pid: ${pid}"
		echo "boot_id: ${boot_id}"
		echo "signal: ${signal}"
		echo "crash_timestamp: ${timestamp}"
		echo "executable: ${exe}"
		echo

		echo "== build ids =="
		echo "postgres (${exe}):"
		readelf -n "$exe" 2>/dev/null | grep 'Build ID' || echo "  (could not read build id)"
		orioledb_lib=$(orioledb_lib_path "$exe")
		if [ -f "$orioledb_lib" ]; then
			echo "orioledb.so (${orioledb_lib}):"
			readelf -n "$orioledb_lib" 2>/dev/null | grep 'Build ID' || echo "  (could not read build id)"
		fi
		echo

		echo "== gdb backtrace (full), lwlocks, locked pages, argv, shared libraries, registers =="
		timeout "$EXTRACTION_TIMEOUT" gdb --batch -quiet \
			-ex "set debug-file-directory ${GDB_DEBUG_DIR}" \
			-ex "file ${exe}" \
			-ex "core-file ${tmpdir}/core" \
			-x "$GDB_CMDS_FILE" \
			2>&1 || echo "(gdb extraction failed or timed out)"
		echo

		echo "== postgresql.log excerpt around crash =="
		# $timestamp looks like "Thu 2026-09-17 11:25:49 UTC (1s ago)" - pull
		# out just the "YYYY-MM-DD HH:MM:SS" portion to match against
		# postgres's own log line prefix (a fixed offset previously grabbed
		# the leading weekday name instead and never matched anything).
		log_ts=$(grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}' <<<"$timestamp" | head -1)
		postgres_log=$(current_postgres_log)
		if [ -n "$log_ts" ] && [ -n "$postgres_log" ] && [ -f "$postgres_log" ]; then
			grep -F "$log_ts" -A 5 -B 20 "$postgres_log" 2>/dev/null | tail -200 ||
				echo "(no log lines found matching ${log_ts} in ${postgres_log})"
		else
			echo "(no crash timestamp or log file available)"
		fi
	} >"$bundle"
	chmod 600 "$bundle"

	# Bundle is written either way at this point, even if the raw-core
	# delete below fails - we don't want a delete failure to make us
	# reprocess (and re-append to) an already-complete bundle next run.
	touch "${state_file}.done"
	if delete_core "$storage_path"; then
		log "pid ${pid}: wrote ${bundle}, deleted raw core"
	else
		log "pid ${pid}: wrote ${bundle}, but WARNING - could not delete raw core at '${storage_path}'"
	fi
}

main() {
	mkdir -p "$STATE_DIR" "$OUTPUT_DIR" "$QUARANTINE_DIR"
	chmod 700 "$STATE_DIR" "$OUTPUT_DIR" "$QUARANTINE_DIR"

	enforce_retention

	# Enumerate via coredumpctl (per INSTRUCTIONS.md's original design),
	# restricted to entries whose raw core is still on disk ("present") -
	# already-removed/historical journal entries are skipped without
	# needing a coredumpctl info round-trip. Field positions match the
	# observed `coredumpctl list` table layout (systemd 255):
	#   TIME(4 tokens) PID UID GID SIG COREFILE EXE SIZE
	local rc=0
	local pid
	while read -r pid; do
		[ -z "$pid" ] && continue
		process_one "$pid" || {
			log "pid ${pid}: processing failed, will retry on next run"
			rc=1
		}
	done < <(coredumpctl --no-legend --no-pager list 2>/dev/null | awk '$9 == "present" {print $5}')

	return "$rc"
}

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
	log "another processor run is already in progress, exiting"
	exit 0
fi

main
