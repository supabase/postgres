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
#  - Works from the core files alone, not the journal: journald can drop a
#    core's entries within minutes on a small root fs (SystemKeepFree), and
#    coredumpctl can't list or export a core without them.

set -euo pipefail

COREDUMP_DIR=/var/lib/systemd/coredump
STATE_DIR=/var/lib/orioledb-coredumps/state
OUTPUT_DIR=/var/lib/orioledb-coredumps/diagnostics
QUARANTINE_DIR=/var/lib/orioledb-coredumps/quarantine

MAX_ATTEMPTS=3
EXTRACTION_TIMEOUT=120
MAX_AGE_DAYS=7
MAX_TOTAL_BYTES=$((300 * 1024 * 1024)) # independent of systemd-coredump's own MaxUse

REALISE_POSTGRES_DEBUG=/var/lib/postgresql/.nix-profile/bin/realise-postgres-debug
GDB_CMDS_FILE=/usr/local/sbin/orioledb-coredump-cmds.gdb
PGDATA_CURRENT_LOGFILES=/var/lib/postgresql/data/current_logfiles

log() {
	echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] $*"
}

# Only ever run under orioledb-coredump.service, so this always executes with
# the unit's hardening (privs, sandboxing) rather than whatever an interactive
# shell happens to have.
if [[ -z ${INVOCATION_ID:-} ]]; then
	echo "This script must be run through orioledb-coredump.service" >&2
	exit 1
fi

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

# Returns success only if the path is actually gone afterward.
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

# realise-postgres-debug returns the debug env, downloading it from the
# binary cache if it isn't already in the store. Resolve it at most once per
# run, and only once there is a postgres core to process.
#
# It refuses to download (exit 3) if that would leave less free space than
# systemd-coredump's KeepFree, the same threshold at which systemd-coredump
# starts deleting cores. That doesn't go away by retrying, unlike the cache
# being unreachable.
DEBUG_ENV=
DEBUG_ENV_RESOLVED=
DEBUG_ENV_PERMANENT_FAILURE=
DEBUG_ENV_UNAVAILABLE_REASON=
resolve_debug_env() {
	[ -n "$DEBUG_ENV_RESOLVED" ] && return 0
	DEBUG_ENV_RESOLVED=1
	local keep_free reserve
	keep_free=$(systemd-analyze cat-config systemd/coredump.conf 2>/dev/null | awk -F= '/^KeepFree=/ {v = $2} END {print v}')
	reserve=$(numfmt --from=iec "${keep_free:-1G}" 2>/dev/null) || reserve=$((1024 * 1024 * 1024))

	# nix's own progress/errors go to stderr, i.e. straight to the journal
	local out rc=0
	out=$(POSTGRES_DEBUG_RESERVE_BYTES="$reserve" timeout -k 10s "$EXTRACTION_TIMEOUT" "$REALISE_POSTGRES_DEBUG") || rc=$?
	if [ "$rc" -eq 0 ] && [ -d "${out}/lib/debug" ]; then
		DEBUG_ENV="$out"
		log "debug symbols: ${DEBUG_ENV}"
	elif [ "$rc" -eq 3 ]; then
		DEBUG_ENV_PERMANENT_FAILURE=1
		DEBUG_ENV_UNAVAILABLE_REASON="not enough disk space to download them"
		log "debug symbols unavailable: not enough disk space to download them"
	else
		DEBUG_ENV_UNAVAILABLE_REASON="download failed"
		log "debug symbols unavailable (realise-postgres-debug exit ${rc}, output: '${out}')"
	fi
}

# Whether the debug env has a .debug file for the ELF at $1, by build-id
debug_file_for() {
	local build_id
	build_id=$(readelf -n "$1" 2>/dev/null | awk '/Build ID/ {print $3}')
	[ -n "$build_id" ] && [ -n "$DEBUG_ENV" ] &&
		[ -f "${DEBUG_ENV}/lib/debug/.build-id/${build_id:0:2}/${build_id:2}.debug" ]
}

# Metadata systemd-coredump attaches to each core file (pid, exe, signal,
# timestamp, ...), one "name=value" per line
core_xattr() {
	getfattr --absolute-names --only-values -n "user.coredump.$2" "$1" 2>/dev/null
}

# Decompress a stored core to $2, by the compression systemd-coredump used
decompress_core() {
	local -a cmd
	case "$1" in
	*.zst) cmd=(zstd -q -d -c --) ;;
	*.xz) cmd=(xz -d -c --) ;;
	*.lz4) cmd=(lz4 -q -d -c --) ;;
	*) cmd=(cat --) ;;
	esac
	timeout "$EXTRACTION_TIMEOUT" "${cmd[@]}" "$1" >"$2"
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

# Handles one stored core file: decide whether it's ours to process, extract
# a diagnostic bundle via GDB, then delete the raw core.
# (1) read the crash's metadata from the core file's xattrs
# (2) decide keep/ignore/quarantine based on prior attempts
# (3) decompress the core and run GDB against it
# (4) write the bundle and delete the raw core. Returns 1 only for failures
#     worth retrying next run (main() logs those); every other outcome is
#     ignored, quarantined, or successfully processed - returns 0.
process_one() {
	local storage_path="$1" key="$2"
	local pid exe signal timestamp signal_name boot_id
	pid=$(core_xattr "$storage_path" pid)
	exe=$(core_xattr "$storage_path" exe)
	signal=$(core_xattr "$storage_path" signal)
	timestamp=$(core_xattr "$storage_path" timestamp)
	boot_id=${key%-*}
	signal_name=unknown
	[[ $signal =~ ^[0-9]+$ ]] && signal_name="SIG$(kill -l "$signal")"
	local state_file="${STATE_DIR}/${key}"

	# .done means "final decision made, never look at this dump again"
	# (processed successfully or quarantined - non-postgres cores are never
	# enumerated in the first place, see main()'s exe filter).
	# .attempts only counts *failed* tries, to cap retries before quarantine.
	[ -f "${state_file}.done" ] && return 0

	local attempts=0
	[ -f "${state_file}.attempts" ] && attempts=$(cat "${state_file}.attempts")
	if [ "$attempts" -ge "$MAX_ATTEMPTS" ]; then
		log "pid ${pid}: exceeded ${MAX_ATTEMPTS} attempts, discarding core (metadata kept in ${QUARANTINE_DIR})"
		getfattr --absolute-names -d -m '^user\.coredump\.' "$storage_path" >"${QUARANTINE_DIR}/${key}.info" 2>&1 || true
		if delete_core "$storage_path"; then
			log "pid ${pid}: raw core deleted"
		else
			log "pid ${pid}: WARNING - could not delete raw core at '${storage_path}'"
		fi
		touch "${state_file}.done"
		return 0
	fi

	# From here on we're committed to actually processing this dump, so
	# count it as an attempt before doing any of the risky (slow, can fail)
	# work below - a crash/timeout past this point still gets retried, up
	# to MAX_ATTEMPTS
	echo $((attempts + 1)) >"${state_file}.attempts"

	# A symbol-less backtrace is much less useful, so leave the core for a
	# later run while there are attempts left, in case the binary cache was
	# only briefly unreachable. The last attempt writes the bundle anyway.
	resolve_debug_env
	if [ -z "$DEBUG_ENV" ] && [ -z "$DEBUG_ENV_PERMANENT_FAILURE" ] &&
		[ $((attempts + 1)) -lt "$MAX_ATTEMPTS" ]; then
		log "pid ${pid}: debug symbols unavailable, will retry"
		return 1
	fi

	# systemd-coredump stores the core compressed; decompress a private,
	# working copy into a root-only scratch dir before handing it to GDB. The trap
	# guarantees that scratch dir is removed when this function returns, no
	# matter which of the several `return`s below fires. `trap ... RETURN`
	# is NOT scoped to this function - it fires on the next return from ANY
	# function (confirmed: without the self-clearing `trap - RETURN` here,
	# main()'s own `return "$rc"` re-fires this same trap, referencing a
	# $tmpdir that's gone out of scope, which is an unbound-variable crash
	# under `set -u` - so it must clear itself once it's run.
	local tmpdir
	tmpdir=$(mktemp -d /tmp/coredump-XXXXXX)
	chmod 700 "$tmpdir"
	trap 'rm -rf "$tmpdir"; trap - RETURN' RETURN

	if ! decompress_core "$storage_path" "${tmpdir}/core"; then
		log "pid ${pid}: decompressing ${storage_path} failed or timed out"
		return 1
	fi

	# Everything from here to the closing "}" is the diagnostic bundle
	# itself, one section at a time, redirected straight to $bundle -
	# there's no in-memory buffering of it, so a slow/hanging step just
	# shows up as a truncated file rather than blocking the whole write.
	# The timestamp xattr is microseconds since the epoch, so it converts
	# straight to a UTC date/time with no string parsing - and that
	# same "YYYY-MM-DD HH:MM:SS" form is what postgres's own log line prefix
	# starts with, so it doubles as the grep key below.
	local crash_timestamp
	crash_timestamp=$(date -u -d "@$((timestamp / 1000000))" '+%Y-%m-%d %H:%M:%S')

	local bundle="${OUTPUT_DIR}/${key}.txt"
	{
		echo "== OrioleDB/PostgreSQL coredump diagnostic bundle =="
		echo "generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
		echo "pid: ${pid}"
		echo "boot_id: ${boot_id}"
		echo "signal: ${signal} (${signal_name})"
		echo "crash_timestamp: ${crash_timestamp} UTC"
		echo "executable: ${exe}"
		echo "debug_symbols: ${DEBUG_ENV:-UNAVAILABLE, ${DEBUG_ENV_UNAVAILABLE_REASON} (backtrace has function names only)}"
		echo

		echo "== build ids =="
		echo "postgres (${exe}):"
		readelf -n "$exe" 2>/dev/null | grep 'Build ID' || echo "  (could not read build id)"
		if debug_file_for "$exe"; then echo "    debug file: present"; else echo "    debug file: MISSING"; fi
		orioledb_lib=$(orioledb_lib_path "$exe")
		if [ -f "$orioledb_lib" ]; then
			echo "orioledb.so (${orioledb_lib}):"
			readelf -n "$orioledb_lib" 2>/dev/null | grep 'Build ID' || echo "  (could not read build id)"
			if debug_file_for "$orioledb_lib"; then echo "    debug file: present"; else echo "    debug file: MISSING"; fi
		fi
		echo

		echo "== gdb backtrace (full), shared libraries, registers, argv, lwlocks, locked pages =="
		timeout "$EXTRACTION_TIMEOUT" gdb --batch -quiet \
			-ex "set debug-file-directory ${DEBUG_ENV:-/nonexistent}/lib/debug" \
			-ex "file ${exe}" \
			-ex "core-file ${tmpdir}/core" \
			-x "$GDB_CMDS_FILE" \
			2>&1 || echo "(gdb extraction failed or timed out)"
		echo

		echo "== postgresql.log excerpt around crash =="
		postgres_log=$(current_postgres_log)
		if [ -n "$postgres_log" ] && [ -f "$postgres_log" ]; then
			grep -F "$crash_timestamp" -A 5 -B 20 "$postgres_log" 2>/dev/null | tail -200 ||
				echo "(no log lines found matching ${crash_timestamp} in ${postgres_log})"
		else
			echo "(no crash timestamp or log file available)"
		fi
	} >"$bundle"
	chmod 600 "$bundle"

	# Bundle is written either way at this point, even if the raw-core
	# delete below fails - we don't want a delete failure to make us
	# reprocess an already-complete bundle next run.
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

	# Core files are named core.<comm>.<uid>.<boot id>.<pid>.<usec>[.<ext>],
	# with any "." in comm escaped. Only postgres's own cores are processed;
	# anything else is left to systemd-coredump's own cleanup.
	local rc=0 core exe key boot_id pid
	local -A present=()
	while IFS= read -r -d '' core; do
		exe=$(core_xattr "$core" exe) || continue
		[[ $exe == */.postgres-wrapped ]] || continue
		IFS=. read -r _ _ _ boot_id pid _ <<<"${core##*/}"
		key="${boot_id}-${pid}"
		present[$key]=1
		process_one "$core" "$key" || {
			log "pid ${pid}: processing failed, will retry on next run"
			rc=1
		}
	done < <(find "$COREDUMP_DIR" -maxdepth 1 -type f -name 'core.*' -print0 2>/dev/null)

	# A core with a failed attempt behind it that's no longer on disk was
	# deleted before we could process it, e.g. by systemd-coredump's KeepFree
	# cleanup when something else crashed. Record that rather than leave it
	# looking like a pending retry forever.
	local attempts_file
	for attempts_file in "$STATE_DIR"/*.attempts; do
		[ -e "$attempts_file" ] || continue
		key=$(basename "$attempts_file" .attempts)
		[ -f "${STATE_DIR}/${key}.done" ] && continue
		[ -n "${present[$key]:-}" ] && continue
		log "${key}: core was removed before it could be processed, no bundle written"
		echo "core was removed from ${COREDUMP_DIR} before it could be processed" >"${QUARANTINE_DIR}/${key}.info"
		touch "${STATE_DIR}/${key}.done"
	done

	return "$rc"
}

main
