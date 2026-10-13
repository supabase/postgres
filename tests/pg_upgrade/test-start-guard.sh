#!/usr/bin/env bash

set -eEuo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

SCRIPTS_DIR="$REPO_ROOT/ansible/files/admin_api_scripts/pg_upgrade_scripts"

# cleanup and on_exit are part of initiate.sh itself, which cannot be sourced.
eval "$(awk '
	/^(cleanup|on_exit)\(\) \{/ { printing = 1 }
	printing { print }
	printing && /^}/ { printing = 0 }
' "$SCRIPTS_DIR/initiate.sh")"

mkdir "$TEST_ROOT/bin"
cat >"$TEST_ROOT/bin/systemctl" <<'SHIM'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$SYSTEMCTL_LOG"
case "$1" in
daemon-reload)
	if [ -f "$FAIL_RELOAD_ONCE" ]; then
		rm "$FAIL_RELOAD_ONCE"
		exit 1
	fi
	;;
is-active)
	printf '%s\n' "${SERVICE_STATE:-inactive}"
	;;
esac
SHIM
cat >"$TEST_ROOT/bin/pgrep" <<'SHIM'
#!/usr/bin/env bash
if [ -n "${PGREP_EMPTY:-}" ]; then
	exit 1
fi
printf '12345\n'
SHIM
cat >"$TEST_ROOT/bin/chown" <<'SHIM'
#!/usr/bin/env bash
exit 0
SHIM
cat >"$TEST_ROOT/bin/rmdir" <<SHIM
#!/usr/bin/env bash
if [ "\$1" = --ignore-fail-on-non-empty ]; then
	shift
fi
exec $(type -P rmdir) "\$@"
SHIM
cat >"$TEST_ROOT/bin/rm" <<SHIM
#!/usr/bin/env bash
if [ "\${FAIL_SHARE_RESTORE:-}" = rm ] && [ "\$1" = "\$POSTGRES_SHARE_DIR" ]; then
	printf 'restore-rm\n' >>"\$SYSTEMCTL_LOG"
	exit 1
fi
exec $(type -P rm) "\$@"
SHIM
cat >"$TEST_ROOT/bin/mv" <<SHIM
#!/usr/bin/env bash
if [ "\${FAIL_SHARE_RESTORE:-}" = mv ] && [ "\$1" = "\${POSTGRES_SHARE_DIR}.bak" ]; then
	printf 'restore-mv\n' >>"\$SYSTEMCTL_LOG"
	exit 1
fi
exec $(type -P mv) "\$@"
SHIM
# The Nix build sandbox on Linux has no /usr/bin/env: point the shims at this bash.
for shim in "$TEST_ROOT/bin/"*; do
	{
		printf '#!%s\n' "$BASH"
		tail -n +2 "$shim"
	} >"$shim.tmp"
	mv "$shim.tmp" "$shim"
done
chmod +x "$TEST_ROOT/bin/"*
export PATH="$TEST_ROOT/bin:$PATH"

log() { printf '%s\n' "$*"; }
retry() {
	printf 'cleanup-abort\n' >>"$SYSTEMCTL_LOG"
	exit 1
}

# shellcheck disable=SC1091
source "$SCRIPTS_DIR/start_guard.sh"

setup() {
	local test_dir
	test_dir=$(mktemp -d "$TEST_ROOT/case.XXXXXX")
	unset IS_CI
	export IS_CI=${IS_CI:-}
	IS_LOCAL_UPGRADE=true
	PGVERSION="guard-test-$$"
	PGDATAOLD="$test_dir/old"
	PGDATANEW="$test_dir/new"
	MOUNT_POINT="$test_dir/mount"
	PG_UPGRADE_LOCK_DROPIN_DIR="$test_dir/postgresql.service.d"
	PG_UPGRADE_LOCK_DROPIN="$PG_UPGRADE_LOCK_DROPIN_DIR/pg-upgrade-lock.conf"
	PG_UPGRADE_PID_LOCK_MARKER="$test_dir/pg-upgrade-source.pid"
	PG_UPGRADE_INITIATE_PID_FILE="$test_dir/pg-upgrade-initiate.pid"
	PG_UPGRADE_START_GUARD="$test_dir/pg-upgrade-start-guard.sh"
	PG_UPGRADE_LOCK_WATCHER_PID=""
	PG_UPGRADE_START_BLOCKED=""
	CLEANUP_STARTED=""
	POSTGRES_SHARE_DIR="$test_dir/share"
	POST_UPGRADE_EXTENSION_SCRIPT="$test_dir/extensions.sql"
	POST_UPGRADE_POSTGRES_PERMS_SCRIPT="$test_dir/perms.sql"
	LOG_FILE="$test_dir/upgrade.log"
	export IS_LOCAL_UPGRADE PGVERSION PGDATAOLD PGDATANEW MOUNT_POINT LOG_FILE
	export POSTGRES_SHARE_DIR POST_UPGRADE_EXTENSION_SCRIPT POST_UPGRADE_POSTGRES_PERMS_SCRIPT
	export PG_UPGRADE_LOCK_DROPIN_DIR PG_UPGRADE_LOCK_DROPIN PG_UPGRADE_PID_LOCK_MARKER
	export PG_UPGRADE_INITIATE_PID_FILE PG_UPGRADE_START_GUARD
	export PG_UPGRADE_LOCK_WATCHER_PID PG_UPGRADE_START_BLOCKED CLEANUP_STARTED
	export SYSTEMCTL_LOG="$test_dir/systemctl.log"
	export FAIL_RELOAD_ONCE="$test_dir/fail-reload"
	export FAIL_SHARE_RESTORE=""
	export SERVICE_STATE=inactive
	mkdir "$PGDATAOLD" "$PGDATANEW"
	: >"$SYSTEMCTL_LOG"
}

assert() {
	if ! "$@"; then
		printf 'FAIL: %s\n' "$*" >&2
		exit 1
	fi
}

test_dropin() {
	setup
	block_postgres_start
	assert grep -qx "ExecCondition=+$(type -P sh) $PG_UPGRADE_START_GUARD $PG_UPGRADE_INITIATE_PID_FILE $PG_UPGRADE_PID_LOCK_MARKER" "$PG_UPGRADE_LOCK_DROPIN"
	assert grep -qx "ExecStartPost=-+$TEST_ROOT/bin/rm -f $PG_UPGRADE_LOCK_DROPIN $PG_UPGRADE_INITIATE_PID_FILE $PG_UPGRADE_PID_LOCK_MARKER $PG_UPGRADE_START_GUARD" "$PG_UPGRADE_LOCK_DROPIN"
	assert grep -qx "ExecStartPost=-+$TEST_ROOT/bin/systemctl daemon-reload" "$PG_UPGRADE_LOCK_DROPIN"
	assert grep -qx 'Restart=no' "$PG_UPGRADE_LOCK_DROPIN"
	assert test -s "$PG_UPGRADE_INITIATE_PID_FILE"
	assert test -s "$PG_UPGRADE_START_GUARD"
	unblock_postgres_start
	assert test ! -e "$PG_UPGRADE_LOCK_DROPIN"
	assert test ! -e "$PG_UPGRADE_INITIATE_PID_FILE"
	assert test ! -e "$PG_UPGRADE_START_GUARD"
	assert test "$(grep -c '^daemon-reload$' "$SYSTEMCTL_LOG")" -eq 2
	assert grep -qx 'reset-failed postgresql' "$SYSTEMCTL_LOG"
	unblock_postgres_start
	assert test "$(grep -c '^reset-failed postgresql$' "$SYSTEMCTL_LOG")" -eq 1
}

test_no_block_reset() {
	setup
	unblock_postgres_start
	if grep -q '^reset-failed postgresql$' "$SYSTEMCTL_LOG"; then
		exit 1
	fi
}

test_block_reload_failure() {
	setup
	touch "$FAIL_RELOAD_ONCE"
	if block_postgres_start; then
		exit 1
	fi
	assert test -f "$PG_UPGRADE_LOCK_DROPIN"
	unblock_postgres_start
	assert test ! -e "$PG_UPGRADE_LOCK_DROPIN"
}

test_unblock_reload_retry() {
	setup
	block_postgres_start
	touch "$FAIL_RELOAD_ONCE"
	if unblock_postgres_start; then
		exit 1
	fi
	assert test ! -e "$PG_UPGRADE_LOCK_DROPIN"
	unblock_postgres_start
	assert test "$(grep -c '^daemon-reload$' "$SYSTEMCTL_LOG")" -eq 3
}

test_owned_pid() {
	setup
	touch "$PGDATANEW/postmaster.pid"
	start_pid_lock_watcher
	wait "$PG_UPGRADE_LOCK_WATCHER_PID"
	assert cmp -s "$PG_UPGRADE_PID_LOCK_MARKER" "$PGDATAOLD/postmaster.pid"
	assert_source_stayed_down
	unblock_postgres_start
	assert test ! -e "$PGDATAOLD/postmaster.pid"
	assert test ! -e "$PG_UPGRADE_PID_LOCK_MARKER"
}

test_foreign_pid() {
	local content
	for content in '' '54321' $'54321\n/data'; do
		setup
		printf '12345\n' >"$PG_UPGRADE_PID_LOCK_MARKER"
		printf '%s' "$content" >"$PGDATAOLD/postmaster.pid"
		if assert_source_stayed_down; then
			exit 1
		fi
		unblock_postgres_start
		assert test -f "$PGDATAOLD/postmaster.pid"
		assert test "$(cat "$PGDATAOLD/postmaster.pid")" = "$content"
	done
	setup
	printf '12345\n' >"$PGDATAOLD/postmaster.pid"
	if assert_source_stayed_down; then
		exit 1
	fi
	unblock_postgres_start
	assert test -f "$PGDATAOLD/postmaster.pid"
}

test_watcher_existing_pid() {
	setup
	touch "$PGDATANEW/postmaster.pid"
	printf '54321\n' >"$PGDATAOLD/postmaster.pid"
	start_pid_lock_watcher
	wait "$PG_UPGRADE_LOCK_WATCHER_PID"
	unblock_postgres_start
	assert test "$(cat "$PGDATAOLD/postmaster.pid")" = 54321
}

test_watcher_abandoned() {
	local watcher_pid_file tries=0
	setup
	export PGREP_EMPTY=1
	watcher_pid_file="$PGDATAOLD/../watcher.pid"
	# a separate shell stands in for a SIGKILLed initiate.sh: it exits, the watcher
	# stays (BASHPID is missing on bash 3.2, so a subshell would not work here)
	# shellcheck disable=SC2016
	"$BASH" -c 'log() { :; }; source "$1"; start_pid_lock_watcher; printf "%s\n" "$PG_UPGRADE_LOCK_WATCHER_PID" >"$2"' _ \
		"$SCRIPTS_DIR/start_guard.sh" "$watcher_pid_file"
	while kill -0 "$(cat "$watcher_pid_file")" 2>/dev/null; do
		tries=$((tries + 1))
		assert test "$tries" -lt 50
		sleep 0.2
	done
	assert test ! -e "$PG_UPGRADE_PID_LOCK_MARKER"
	unset PGREP_EMPTY
}

test_active_source() {
	local state
	for state in active activating reloading; do
		setup
		export SERVICE_STATE="$state"
		if assert_source_stayed_down; then
			exit 1
		fi
	done
}

test_start_guard() {
	local live dead
	setup
	block_postgres_start
	sleep 60 &
	live=$!
	(exit 0) &
	dead=$!
	wait "$dead"
	guard_exit() {
		local exit_code=0
		sh -c "$(sed -n 's/^ExecCondition=+//p' "$PG_UPGRADE_LOCK_DROPIN")" || exit_code=$?
		printf '%s\n' "$exit_code"
	}
	assert test "$(guard_exit)" -eq 255
	printf '%s\n' "$dead" >"$PG_UPGRADE_INITIATE_PID_FILE"
	assert test "$(guard_exit)" -eq 0
	printf '%s\n' "$live" >"$PG_UPGRADE_PID_LOCK_MARKER"
	assert test "$(guard_exit)" -eq 255
	printf '%s\n' "$live" >"$PG_UPGRADE_INITIATE_PID_FILE"
	printf '%s\n' "$dead" >"$PG_UPGRADE_PID_LOCK_MARKER"
	assert test "$(guard_exit)" -eq 255
	printf '%s\n' "$dead" >"$PG_UPGRADE_INITIATE_PID_FILE"
	printf '%s\n' "$dead" >"$PG_UPGRADE_PID_LOCK_MARKER"
	assert test "$(guard_exit)" -eq 0
	printf 'not-a-pid\n' >"$PG_UPGRADE_INITIATE_PID_FILE"
	: >"$PG_UPGRADE_PID_LOCK_MARKER"
	assert test "$(guard_exit)" -eq 0
	rm -f "$PG_UPGRADE_INITIATE_PID_FILE" "$PG_UPGRADE_PID_LOCK_MARKER"
	assert test "$(guard_exit)" -eq 0
	kill "$live"
	wait "$live" 2>/dev/null || true
}

test_dropin_expiry() {
	local exec_start_post
	setup
	block_postgres_start
	printf '%s\n' 12345 >"$PG_UPGRADE_PID_LOCK_MARKER"
	exec_start_post=$(grep -F "ExecStartPost=-+$TEST_ROOT/bin/rm " "$PG_UPGRADE_LOCK_DROPIN")
	sh -c "${exec_start_post#ExecStartPost=-+}"
	assert test ! -e "$PG_UPGRADE_LOCK_DROPIN"
	assert test ! -e "$PG_UPGRADE_INITIATE_PID_FILE"
	assert test ! -e "$PG_UPGRADE_PID_LOCK_MARKER"
	assert test ! -e "$PG_UPGRADE_START_GUARD"
	unblock_postgres_start
}

test_exit_cleanup() {
	local trigger exit_code expected_code
	for trigger in failure TERM INT clean-exit cleanup-exit already-cleaned restore-rm restore-mv; do
		setup
		mkdir "${POSTGRES_SHARE_DIR}.bak" "$POSTGRES_SHARE_DIR.new"
		ln -s "$POSTGRES_SHARE_DIR.new" "$POSTGRES_SHARE_DIR"
		exit_code=0
		expected_code=1
		case "$trigger" in
		TERM | cleanup-exit) expected_code=143 ;;
		INT) expected_code=130 ;;
		already-cleaned) expected_code=0 ;;
		restore-rm) export FAIL_SHARE_RESTORE=rm ;;
		restore-mv) export FAIL_SHARE_RESTORE=mv ;;
		esac
		"$BASH" -s "$trigger" <<-'TRAP_TEST' || exit_code=$?
			set -eEuo pipefail
			if [ "$1" = cleanup-exit ]; then
				cleanup() {
					printf "cleanup-abort\n" >>"$SYSTEMCTL_LOG"
					exit 1
				}
			fi
			trap on_exit EXIT
			trap "cleanup failed" ERR
			trap "exit 143" TERM
			trap "exit 130" INT
			block_postgres_start
			touch "$FAIL_RELOAD_ONCE"
			case "$1" in
			TERM | INT) kill -s "$1" "$$" ;;
			clean-exit) exit 0 ;;
			cleanup-exit) rm "$FAIL_RELOAD_ONCE"; exit 143 ;;
			already-cleaned) rm "$FAIL_RELOAD_ONCE"; CLEANUP_STARTED=1; exit 0 ;;
			*) false ;;
			esac
		TRAP_TEST
		assert test "$exit_code" -eq "$expected_code"
		assert test ! -e "$PG_UPGRADE_LOCK_DROPIN"
		assert test ! -e "$FAIL_RELOAD_ONCE"
		assert test "$(tail -n 2 "$SYSTEMCTL_LOG")" = $'daemon-reload\nreset-failed postgresql'
		case "$trigger" in
		already-cleaned)
			assert test "$(grep -c '^daemon-reload$' "$SYSTEMCTL_LOG")" -eq 2
			if grep -q '^cleanup-abort$' "$SYSTEMCTL_LOG"; then exit 1; fi
			;;
		cleanup-exit)
			assert test "$(grep -c '^daemon-reload$' "$SYSTEMCTL_LOG")" -eq 2
			assert test "$(grep -c '^cleanup-abort$' "$SYSTEMCTL_LOG")" -eq 1
			;;
		*)
			assert test "$(grep -c '^daemon-reload$' "$SYSTEMCTL_LOG")" -eq 3
			assert test "$(grep -c '^cleanup-abort$' "$SYSTEMCTL_LOG")" -eq 1
			case "$trigger" in
			restore-rm | restore-mv) assert grep -qx "$trigger" "$SYSTEMCTL_LOG" ;;
			*) assert test ! -L "$POSTGRES_SHARE_DIR" ;;
			esac
			;;
		esac
	done
}

export -f log retry block_postgres_start unblock_postgres_start assert_source_stayed_down cleanup on_exit
for test_name in test_dropin test_no_block_reset test_block_reload_failure test_unblock_reload_retry test_owned_pid test_foreign_pid test_watcher_existing_pid test_watcher_abandoned test_active_source test_start_guard test_dropin_expiry test_exit_cleanup; do
	case_output="$TEST_ROOT/$test_name.log"
	trap 'exit_code=$?; cat "$case_output"; exit "$exit_code"' ERR
	(
		trap - ERR
		"$test_name"
	) >"$case_output" 2>&1
	printf 'PASS: %s\n' "$test_name"
done
