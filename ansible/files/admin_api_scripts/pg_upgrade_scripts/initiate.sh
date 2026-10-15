#! /usr/bin/env bash

## This script is run on the old (source) instance, disabling extensions
## containing regtypes and running pg_upgrade --link in place on its own data
## volume, which the worker then moves to the newly launched instance.
## It reports the current status of the upgrade process to /tmp/pg-upgrade-status,
## which can then be subsequently checked through check.sh.

# Extensions to disable before running pg_upgrade.
# Running an upgrade with these extensions enabled will result in errors due to
# them depending on regtypes referencing system OIDs or outdated library files.
EXTENSIONS_TO_DISABLE=(
	"amcheck" # avoids leaving 1.4-only functions ungranted after the version bump
	"pg_backtrace"
	"pg_graphql"
	"pg_stat_monitor"
	"plpgsql_check" # old versioned library clashes with the preloaded new one
)

PG14_EXTENSIONS_TO_DISABLE=(
	"wrappers"
	"pgrouting"
)

PG13_EXTENSIONS_TO_DISABLE=(
	"pgrouting"
)

set -eEuo pipefail

SCRIPT_DIR=$(dirname -- "$0")
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

IS_CI=${IS_CI:-}
IS_LOCAL_UPGRADE=${IS_LOCAL_UPGRADE:-}
IS_NIX_UPGRADE=${IS_NIX_UPGRADE:-}
IS_NIX_BASED_SYSTEM="false"

PGVERSION=$1
DATA_ROOT="/data"
LOG_FILE="/var/log/pg-upgrade-initiate.log"
# Set once pg_upgrade --link runs for real: from then on the old cluster shares its files with the
# new one and must not be started again, so a failure is rolled back by the worker from the
# snapshot it took before /initiate, not by restarting Postgres here.
LINK_STARTED=""

POST_UPGRADE_EXTENSION_SCRIPT="/tmp/pg_upgrade/pg_upgrade_extensions.sql"
POST_UPGRADE_POSTGRES_PERMS_SCRIPT="/tmp/pg_upgrade/pg_upgrade_postgres_perms.sql"
OLD_PGVERSION=$(run_sql -A -t -c "SHOW server_version;")

# Skip locale settings if both versions are PostgreSQL 16+
if ! [[ ${OLD_PGVERSION%%.*} -ge 16 && ${PGVERSION%%.*} -ge 16 ]]; then
	SERVER_LC_COLLATE=$(run_sql -A -t -c "SHOW lc_collate;")
	SERVER_LC_CTYPE=$(run_sql -A -t -c "SHOW lc_ctype;")
fi

SERVER_ENCODING=$(run_sql -A -t -c "SHOW server_encoding;")

POSTGRES_CONFIG_PATH="/etc/postgresql/postgresql.conf"
PGBINOLD="/usr/lib/postgresql/bin"

PG_UPGRADE_BIN_DIR="/tmp/pg_upgrade_bin/$PGVERSION"
NIX_INSTALLER_PATH="/tmp/persistent/nix-installer"
NIX_INSTALLER_PACKAGE_PATH="$NIX_INSTALLER_PATH.tar.gz"

if [ -L "$PGBINOLD/pg_upgrade" ]; then
	BINARY_PATH=$(readlink -f "$PGBINOLD/pg_upgrade")
	if [[ $BINARY_PATH == *"nix"* ]]; then
		IS_NIX_BASED_SYSTEM="true"
	fi
fi

# If upgrading from older major PG versions, disable specific extensions
if [[ $OLD_PGVERSION =~ ^14.* ]]; then
	EXTENSIONS_TO_DISABLE+=("${PG14_EXTENSIONS_TO_DISABLE[@]}")
elif [[ $OLD_PGVERSION =~ ^13.* ]]; then
	EXTENSIONS_TO_DISABLE+=("${PG13_EXTENSIONS_TO_DISABLE[@]}")
elif [[ $OLD_PGVERSION =~ ^12.* ]]; then
	POSTGRES_CONFIG_PATH="/etc/postgresql/12/main/postgresql.conf"
	PGBINOLD="/usr/lib/postgresql/12/bin"
fi

if [ -n "$IS_CI" ]; then
	PGBINOLD="$(pg_config --bindir)"
	log "Running in CI mode; using pg_config bindir: $PGBINOLD"
	log "PGVERSION: $PGVERSION"
fi

OLD_BOOTSTRAP_USER=$(run_sql -A -t -c "select rolname from pg_authid where oid = 10;")

cleanup() {
	UPGRADE_STATUS=${1:-"failed"}
	EXIT_CODE=${?:-0}

	if [ "$UPGRADE_STATUS" = "failed" ]; then
		EXIT_CODE=1
	fi

	if [ "$UPGRADE_STATUS" = "failed" ]; then
		log "Upgrade job failed. Cleaning up and exiting."
	fi

	if [ -z "$IS_CI" ] && [ -z "$IS_LOCAL_UPGRADE" ]; then
		# Restore timers before anything below: nearly every later step (chown,
		# bare retry postgres restart, SQL) can fail under set -e and kill this
		# trap mid-way, and the restore must not sit behind that. Warn-only for
		# the same reason — aborting here would also leave the status file
		# stuck at "running".
		enable_conflicting_timers || log "WARNING: failed to re-enable one or more timers; check 'systemctl list-timers --all' on this host"
	fi

	# pg_upgrade writes into the new cluster's directory: pgdata_new until the swap, pgdata after
	for output_dir in "$DATA_ROOT/pgdata_new" "$DATA_ROOT/pgdata"; do
		if [ -d "$output_dir/pg_upgrade_output.d/" ]; then
			log "Copying pg_upgrade output from $output_dir to /var/log"
			cp -R "$output_dir/pg_upgrade_output.d/" /var/log/ || true
			chown -R postgres:postgres /var/log/pg_upgrade_output.d/ || true
			chmod -R 0750 /var/log/pg_upgrade_output.d/ || true
			ship_logs "$LOG_FILE" || true
			tail -n +1 /var/log/pg_upgrade_output.d/*/* >/var/log/pg_upgrade_output.d/pg_upgrade.log || true
			ship_logs "/var/log/pg_upgrade_output.d/pg_upgrade.log" || true
			break
		fi
	done

	if [ -L "/usr/share/postgresql/${PGVERSION}" ]; then
		rm "/usr/share/postgresql/${PGVERSION}"

		if [ -f "/usr/share/postgresql/${PGVERSION}.bak" ]; then
			mv "/usr/share/postgresql/${PGVERSION}.bak" "/usr/share/postgresql/${PGVERSION}"
		fi

		if [ -d "/usr/share/postgresql/${PGVERSION}.bak" ]; then
			mv "/usr/share/postgresql/${PGVERSION}.bak" "/usr/share/postgresql/${PGVERSION}"
		fi
	fi

	# Always, whatever happened: the worker restores a failed original from the snapshot and
	# starts it, and Postgres has to come up with it
	if [ -z "$IS_CI" ]; then
		systemctl enable postgresql || log "WARNING: failed to re-enable the postgresql unit"
	fi

	# Only while the old cluster is still intact. Warn-only so a failing restore still flips the
	# status to failed instead of leaving it stuck at running; the worker restores from the
	# snapshot either way.
	if [ "$UPGRADE_STATUS" = "failed" ] && [ -z "$LINK_STARTED" ]; then
		restore_old_cluster || log "WARNING: failed to bring the old cluster back; the worker restores it from the snapshot"
	fi

	echo "$UPGRADE_STATUS" >/tmp/pg-upgrade-status

	if [ -z "$IS_CI" ]; then
		exit "$EXIT_CODE"
	else
		log "CI run complete with code ${EXIT_CODE}. Exiting."
		exit "$EXIT_CODE"
	fi
}

# Brings the untouched old cluster back into service after a failure before pg_upgrade --link ran.
# Failures are tracked in rc rather than left to set -e: this is called as the left operand of
# ||, which disables errexit for the whole body (see complete.sh's execute_patches).
restore_old_cluster() {
	local rc=0

	log "Restarting postgresql"
	if [ -z "$IS_CI" ]; then
		retry 5 systemctl restart postgresql || rc=1
	else
		CI_start_postgres || rc=1
	fi

	retry 8 pg_isready -h localhost -U supabase_admin || rc=1

	log "Re-enabling extensions"
	if [ -f $POST_UPGRADE_EXTENSION_SCRIPT ]; then
		retry 5 run_sql -f $POST_UPGRADE_EXTENSION_SCRIPT || rc=1
	fi

	log "Removing SUPERUSER grant from postgres"
	retry 5 run_sql -c "ALTER USER postgres WITH NOSUPERUSER;" || rc=1

	log "Resetting postgres database connection limit"
	retry 5 run_sql -c "ALTER DATABASE postgres CONNECTION LIMIT -1;" || rc=1

	log "Making sure postgres still has access to pg_shadow"
	cat <<EOF >>$POST_UPGRADE_POSTGRES_PERMS_SCRIPT
DO \$\$
begin
  if exists (select from pg_authid where rolname = 'pg_read_all_data') then
    execute('grant pg_read_all_data to postgres');
  end if;
end
\$\$;
grant pg_signal_backend to postgres;
EOF

	if [ -f $POST_UPGRADE_POSTGRES_PERMS_SCRIPT ]; then
		retry 5 run_sql -f $POST_UPGRADE_POSTGRES_PERMS_SCRIPT || rc=1
	fi

	return $rc
}

function handle_extensions {
	if [ -z "$IS_CI" ]; then
		retry 5 systemctl restart postgresql
	else
		CI_start_postgres
	fi

	retry 8 pg_isready -h localhost -U supabase_admin

	rm -f $POST_UPGRADE_EXTENSION_SCRIPT
	touch $POST_UPGRADE_EXTENSION_SCRIPT

	PASSWORD_ENCRYPTION_SETTING=$(run_sql -A -t -c "SHOW password_encryption;")
	if [ "$PASSWORD_ENCRYPTION_SETTING" = "md5" ]; then
		echo "ALTER SYSTEM SET password_encryption = 'md5';" >>$POST_UPGRADE_EXTENSION_SCRIPT
	fi

	cat <<EOF >>$POST_UPGRADE_EXTENSION_SCRIPT
ALTER SYSTEM SET jit = off;
SELECT pg_reload_conf();
EOF

	# Rescope before dropping extensions: the fixed triggers are carried into the new
	# cluster by pg_upgrade, so both the post-upgrade re-enable and the failure-path
	# re-enable below fire them. Fail-soft: a broken rescope should not block the
	# upgrade — but retry first, since a skipped rescope means the recreation of
	# these extensions silently loses their wiring.
	retry 3 rescope_extension_event_triggers || log "WARNING: failed to rescope extension event triggers"

	# Disable extensions if they're enabled
	# Generate SQL script to re-enable them after upgrade
	for EXTENSION in "${EXTENSIONS_TO_DISABLE[@]}"; do
		EXTENSION_ENABLED=$(run_sql -A -t -c "SELECT EXISTS(SELECT 1 FROM pg_extension WHERE extname = '${EXTENSION}');")
		if [ "$EXTENSION_ENABLED" = "t" ]; then
			log "Disabling extension ${EXTENSION}"
			run_sql -c "DROP EXTENSION IF EXISTS ${EXTENSION} CASCADE;"
			cat <<EOF >>$POST_UPGRADE_EXTENSION_SCRIPT
DO \$\$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = '${EXTENSION}') THEN
        CREATE EXTENSION IF NOT EXISTS ${EXTENSION} CASCADE;
    END IF;
END;
\$\$;
EOF
		fi
	done
}

function initiate_upgrade {
	# Before anything destructive: no || true here, a timer firing mid-upgrade is
	# exactly what this guards against, and failing now leaves the project untouched.
	# Interrupting an apt-daily run can leave dpkg half-configured; step 2's
	# `dpkg --configure -a` repairs that a moment later.
	if [ -z "$IS_CI" ] && [ -z "$IS_LOCAL_UPGRADE" ]; then
		log "0. Masking conflicting systemd timers"
		retry 3 disable_conflicting_timers
	fi

	# 2 GiB: enough headroom for the Nix store realize onto / (see check_free_space)
	check_free_space $((2 * 1024 * 1024))

	SHARED_PRELOAD_LIBRARIES=$(grep '^[[:space:]]*shared_preload_libraries' "$POSTGRES_CONFIG_PATH" | sed "s/shared_preload_libraries =\s\{0,1\}'\(.*\)'.*/\1/")

	# Wrappers officially launched in PG15; PG14 version is incompatible
	if [[ $OLD_PGVERSION =~ 14* ]]; then
		SHARED_PRELOAD_LIBRARIES=$(echo "$SHARED_PRELOAD_LIBRARIES" | sed "s/wrappers//" | xargs)
	fi

	# Timescale is no longer supported for PG17+ upgrades
	if [[ $PGVERSION != "15" ]]; then
		SHARED_PRELOAD_LIBRARIES=$(echo "$SHARED_PRELOAD_LIBRARIES" | sed "s/timescaledb//" | xargs)
	fi

	SHARED_PRELOAD_LIBRARIES=$(echo "$SHARED_PRELOAD_LIBRARIES" | sed "s/pg_cron//" | xargs)
	SHARED_PRELOAD_LIBRARIES=$(echo "$SHARED_PRELOAD_LIBRARIES" | sed "s/pg_net//" | xargs)
	SHARED_PRELOAD_LIBRARIES=$(echo "$SHARED_PRELOAD_LIBRARIES" | sed "s/check_role_membership//" | xargs)
	SHARED_PRELOAD_LIBRARIES=$(echo "$SHARED_PRELOAD_LIBRARIES" | sed "s/safeupdate//" | xargs)
	SHARED_PRELOAD_LIBRARIES=$(echo "$SHARED_PRELOAD_LIBRARIES" | sed "s/pg_backtrace//" | xargs)

	# Exclude empty-string entries, as well as leading/trailing commas and spaces resulting from the above lib exclusions
	#  i.e. " , pg_stat_statements, , pgsodium, " -> "pg_stat_statements, pgsodium"
	SHARED_PRELOAD_LIBRARIES=$(echo "$SHARED_PRELOAD_LIBRARIES" | tr ',' ' ' | tr -s ' ' | tr ' ' ', ')

	# Account for trailing comma
	# eg. "...,auto_explain,pg_tle,plan_filter," -> "...,auto_explain,pg_tle,plan_filter"
	if [[ ${SHARED_PRELOAD_LIBRARIES: -1} == "," ]]; then
		# clean up trailing comma
		SHARED_PRELOAD_LIBRARIES=$(echo "$SHARED_PRELOAD_LIBRARIES" | sed "s/.$//" | xargs)
	fi

	PGDATAOLD=$(grep '^[[:space:]]*data_directory' "$POSTGRES_CONFIG_PATH" | sed "s/data_directory = '\(.*\)'.*/\1/")

	# Older AMIs point data_directory at the /var/lib/postgresql/data symlink; the directory swap
	# after pg_upgrade needs the real path on the data volume
	PGDATAOLD_REAL=$(readlink -f "$PGDATAOLD")
	if [ "$PGDATAOLD_REAL" != "$DATA_ROOT/pgdata" ]; then
		log "ERROR: data_directory $PGDATAOLD resolves to $PGDATAOLD_REAL, expected $DATA_ROOT/pgdata; aborting upgrade."
		false
	fi
	if [ -e "$DATA_ROOT/pgdata_old" ]; then
		log "ERROR: $DATA_ROOT/pgdata_old exists: an earlier in-place upgrade left this volume in an unknown state; aborting upgrade."
		false
	fi
	# A worker still running the copy-mode flow attaches the new instance's volume here and
	# expects the upgrade to land on it; fail before touching anything instead
	if [ -z "$IS_CI" ] && [ -z "$IS_LOCAL_UPGRADE" ] && find_block_device xvdp >/dev/null; then
		log "ERROR: a migration volume is attached at xvdp, but these scripts upgrade in place; aborting upgrade."
		false
	fi
	# 1 GiB on the data volume: --link shares the relation files, but initdb and the new catalog
	# still need room
	check_free_space $((1024 * 1024)) "$DATA_ROOT"

	# Check if old cluster has data checksums enabled
	CHECKSUM_VERSION=$("$PGBINOLD/pg_controldata" "$PGDATAOLD" | grep -i checksum | awk '{print $NF}')
	if [ "$CHECKSUM_VERSION" != "0" ]; then
		CHECKSUM_FLAG="--data-checksums"
	else
		CHECKSUM_FLAG=""
	fi

	PGDATANEW="$DATA_ROOT/pgdata_new"

	# running upgrade using at least 1 cpu core
	WORKERS=$(nproc | awk '{ print ($1 == 1 ? 1 : $1 - 1) }')

	# To make nix-based upgrades work for testing, create a pg binaries tarball with the following contents:
	#  - nix_flake_version - a7189a68ed4ea78c1e73991b5f271043636cf074
	# Where the value is the commit hash of the nix flake that contains the binaries

	if [ -n "$IS_LOCAL_UPGRADE" ]; then
		mkdir -p "$PG_UPGRADE_BIN_DIR"
		mkdir -p /tmp/persistent/
		if [ -n "$NIX_FLAKE_VERSION" ]; then
			echo "$NIX_FLAKE_VERSION" >"$PG_UPGRADE_BIN_DIR/nix_flake_version"
		else
			echo "a7189a68ed4ea78c1e73991b5f271043636cf074" >"$PG_UPGRADE_BIN_DIR/nix_flake_version"
		fi

		tar -czf "/tmp/persistent/pg_upgrade_bin.tar.gz" -C "/tmp/pg_upgrade_bin" .
		rm -rf /tmp/pg_upgrade_bin/
	fi

	log "1. Extracting pg_upgrade binaries"
	mkdir -p "/tmp/pg_upgrade_bin"
	tar zxf "/tmp/persistent/pg_upgrade_bin.tar.gz" -C "/tmp/pg_upgrade_bin"

	PGSHARENEW="$PG_UPGRADE_BIN_DIR/share"

	if [ -f "$PG_UPGRADE_BIN_DIR/nix_flake_version" ]; then
		IS_NIX_UPGRADE="true"
		NIX_FLAKE_VERSION=$(cat "$PG_UPGRADE_BIN_DIR/nix_flake_version")

		if [ "$IS_NIX_BASED_SYSTEM" = "false" ]; then
			if [ ! -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
				if ! command -v nix >/dev/null; then
					log "1.1. Nix is not installed; installing."

					if [ -f "$NIX_INSTALLER_PACKAGE_PATH" ]; then
						log "1.1.1. Installing Nix using the provided installer"
						tar -xzf "$NIX_INSTALLER_PACKAGE_PATH" -C /tmp/persistent/
						chmod +x "$NIX_INSTALLER_PATH"
						"$NIX_INSTALLER_PATH" install --no-confirm \
							--extra-conf "substituters = https://cache.nixos.org https://nix-postgres-artifacts.s3.amazonaws.com" \
							--extra-conf "trusted-public-keys = nix-postgres-artifacts:dGZlQOvKcNEjvT7QEAJbcV6b6uk7VF/hWMjhYleiaLI= cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
					else
						log "1.1.1. Installing Nix using the official installer"
						sh <(curl -L https://releases.nixos.org/nix/nix-2.34.6/install) --yes --daemon --nix-extra-conf-file /dev/stdin <<EXTRA_NIX_CONF
extra-experimental-features = nix-command flakes
extra-substituters = https://nix-postgres-artifacts.s3.amazonaws.com
extra-trusted-public-keys = nix-postgres-artifacts:dGZlQOvKcNEjvT7QEAJbcV6b6uk7VF/hWMjhYleiaLI=
EXTRA_NIX_CONF
					fi
				else
					log "1.1. Nix is installed; moving on."
				fi
			fi
		fi

		log "1.2. Fetching store path for flake revision: $NIX_FLAKE_VERSION"
		# shellcheck disable=SC1091
		source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
		nix --version
		nix-collect-garbage -d >/tmp/pg_upgrade-nix-gc.log 2>&1 || true

		# Determine system architecture
		ARCH=$(uname -m)
		if [ "$ARCH" = "aarch64" ]; then
			SYSTEM="aarch64-linux"
		elif [ "$ARCH" = "x86_64" ]; then
			SYSTEM="x86_64-linux"
		else
			log "ERROR: Unsupported architecture: $ARCH"
			# fail as a command, not exit 1: exit skips the ERR trap, so cleanup
			# would never restore the masked timers or write the status file
			false
		fi

		# Fetch store path from catalog (avoids expensive nix eval - prevents OOM on small instances)
		# Each postgres version has its own catalog file: {git_sha}-psql_{version}.json
		CATALOG_S3="s3://supabase-internal-artifacts/nix-catalog/${NIX_FLAKE_VERSION}-psql_${PGVERSION}-${SYSTEM}.json"
		CATALOG_LOCAL="/tmp/nix-catalog-${NIX_FLAKE_VERSION}-psql_${PGVERSION}-${SYSTEM}.json"
		log "Fetching catalog from: $CATALOG_S3"

		if ! aws s3 cp "$CATALOG_S3" "$CATALOG_LOCAL" --region ap-southeast-1; then
			log "ERROR: Failed to fetch catalog from $CATALOG_S3"
			false # not exit: let the ERR trap run cleanup
		fi

		STORE_PATH=$(jq -r ".\"${SYSTEM}\"" "$CATALOG_LOCAL")

		if [ -z "$STORE_PATH" ] || [ "$STORE_PATH" = "null" ]; then
			log "ERROR: Could not find store path in catalog for ${SYSTEM}"
			log "Catalog contents:"
			jq . "$CATALOG_LOCAL"
			false # not exit: let the ERR trap run cleanup
		fi

		log "Store path: $STORE_PATH"

		# Realize the closure from the binary cache.
		#
		# nix-store -r can stall indefinitely on a dropped S3 connection without
		# erroring out (its own download timeout doesn't reliably fire), so guard each
		# attempt with a timeout and retry. Each path downloads atomically: already-
		# registered paths are skipped on retry but an in-flight NAR restarts from
		# 0%. Failing as a normal command (not exit 1) lets the ERR trap run cleanup
		# and record "failed" instead of hanging.
		#
		# Re-check free space here: the earlier check at the top of initiate_upgrade
		# only guarantees headroom at entry, and the tarball extraction / nix install
		# / catalog download above can already have eaten into that reserve before
		# the realize (the actual big consumer) starts.
		check_free_space $((2 * 1024 * 1024))

		nix_store_ok="false"
		for attempt in 1 2 3; do
			if timeout -k 10s 120s nix-store -r --quiet "$STORE_PATH"; then
				nix_store_ok="true"
				break
			fi
			if [ "$attempt" -lt 3 ]; then
				log "WARNING: nix-store -r attempt ${attempt}/3 for $STORE_PATH failed or stalled (>=120s + up to 10s kill grace); retrying"
			else
				log "ERROR: nix-store -r failed after 3 attempts for $STORE_PATH"
			fi
		done
		[ "$nix_store_ok" = "true" ]

		# Closure is realized, so the multi-GB Nix reserve is no longer needed; just
		# confirm enough room remains for the lighter apt/locale-gen work still ahead.
		check_free_space $((512 * 1024))

		PG_UPGRADE_BIN_DIR="$STORE_PATH"
		PGSHARENEW="$PG_UPGRADE_BIN_DIR/share/postgresql"
	fi

	PGBINNEW="$PG_UPGRADE_BIN_DIR/bin"
	PGLIBNEW="$PG_UPGRADE_BIN_DIR/lib"

	# copy upgrade-specific pgsodium_getkey script into the share dir
	chmod +x "$SCRIPT_DIR/pgsodium_getkey.sh"
	mkdir -p "$PGSHARENEW/extension"
	cp "$SCRIPT_DIR/pgsodium_getkey.sh" "$PGSHARENEW/extension/pgsodium_getkey"
	if [ -d "/var/lib/postgresql/extension/" ]; then
		cp "$SCRIPT_DIR/pgsodium_getkey.sh" "/var/lib/postgresql/extension/pgsodium_getkey"
		chown postgres:postgres "/var/lib/postgresql/extension/pgsodium_getkey"
	fi

	chown -R postgres:postgres "/tmp/pg_upgrade_bin/$PGVERSION"

	# upgrade job outputs a log in the cwd; needs write permissions
	mkdir -p /tmp/pg_upgrade/
	chown -R postgres:postgres /tmp/pg_upgrade/
	cd /tmp/pg_upgrade/

	# Fixing erros generated by previous dpkg executions (package upgrades et co)
	log "2. Fixing potential errors generated by dpkg"
	log "2.1 Killing off any old hanging apt-get processes"
	# One hour is old enough to be bad
	pkill -f apt-get --older 3600 2>/dev/null || log "No hanging apt-get processes found"
	DEBIAN_FRONTEND=noninteractive dpkg --configure -a --force-confold || true # handle errors generated by dpkg

	# Needed for PostGIS, since it's compiled with Protobuf-C support now
	log "3. Installing libprotobuf-c1 and libicu66 if missing"
	if ! apt list --installed libprotobuf-c1 | grep -q installed; then
		apt-get -o DPkg::Lock::Timeout=600 update -y                # wait up to 10 minutes for any dpkg locks to clear before updating package lists
		apt --fix-broken install -y libprotobuf-c1 libicu66 || true # apt has builtin 2 minute wait lock
	fi

	log "4. Setup locale if required"
	if ! grep -q "^en_US.UTF-8" /etc/locale.gen; then
		echo "en_US.UTF-8 UTF-8" >>/etc/locale.gen
	fi
	if ! grep -q "^C.UTF-8" /etc/locale.gen; then
		echo "C.UTF-8 UTF-8" >>/etc/locale.gen
	fi
	locale-gen

	log "7. Disabling extensions and generating post-upgrade script"
	handle_extensions

	log "8.1. Granting SUPERUSER to postgres user"
	run_sql -c "ALTER USER postgres WITH SUPERUSER;"

	if [ "$OLD_BOOTSTRAP_USER" = "postgres" ]; then
		log "8.2. Swap postgres & supabase_admin roles as we're upgrading a project with postgres as bootstrap user"
		swap_postgres_and_supabase_admin
	fi

	if [ -z "$IS_NIX_UPGRADE" ]; then
		if [ -d "/usr/share/postgresql/${PGVERSION}" ]; then
			mv "/usr/share/postgresql/${PGVERSION}" "/usr/share/postgresql/${PGVERSION}.bak"
		fi

		ln -s "$PGSHARENEW" "/usr/share/postgresql/${PGVERSION}"
		cp --remove-destination "$PGLIBNEW"/*.control "$PGSHARENEW/extension/"
		cp --remove-destination "$PGLIBNEW"/*.sql "$PGSHARENEW/extension/"

		export LD_LIBRARY_PATH="${PGLIBNEW}"
	fi

	log "9. Creating new data directory, initializing database"
	rm -rf "${PGDATANEW:?}"
	install -d -o postgres -g postgres -m 0750 "$PGDATANEW"

	if [ "$IS_NIX_UPGRADE" = "true" ]; then
		if [[ ${PGVERSION%%.*} -ge 16 ]]; then
			LC_ALL=en_US.UTF-8 LC_CTYPE=en_US.UTF-8 LC_COLLATE=en_US.UTF-8 LANGUAGE=en_US.UTF-8 LANG=en_US.UTF-8 LOCALE_ARCHIVE=/usr/lib/locale/locale-archive su -c ". /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh && $PGBINNEW/initdb --allow-group-access $CHECKSUM_FLAG --encoding=$SERVER_ENCODING --locale-provider=icu --icu-locale=en_US.UTF-8 -L $PGSHARENEW -D $PGDATANEW/ --username=supabase_admin" -s "$SHELL" postgres
		else
			LC_ALL=en_US.UTF-8 LC_CTYPE=$SERVER_LC_CTYPE LC_COLLATE=$SERVER_LC_COLLATE LANGUAGE=en_US.UTF-8 LANG=en_US.UTF-8 LOCALE_ARCHIVE=/usr/lib/locale/locale-archive su -c ". /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh && $PGBINNEW/initdb --allow-group-access $CHECKSUM_FLAG --encoding=$SERVER_ENCODING --lc-collate=$SERVER_LC_COLLATE --lc-ctype=$SERVER_LC_CTYPE -L $PGSHARENEW -D $PGDATANEW/ --username=supabase_admin" -s "$SHELL" postgres
		fi
	else
		su -c "$PGBINNEW/initdb --allow-group-access $CHECKSUM_FLAG -L $PGSHARENEW -D $PGDATANEW/ --username=supabase_admin" -s "$SHELL" postgres

	fi

	# This line avoids the need to supply the supabase_admin password on the old
	# instance, since pg_upgrade connects to the db as supabase_admin using unix
	# sockets, which is gated behind scram-sha-256 per pg_hba.conf.j2. The new
	# instance is unaffected.
	if ! grep -q "local all supabase_admin trust" /etc/postgresql/pg_hba.conf; then
		echo "local all supabase_admin trust
$(cat /etc/postgresql/pg_hba.conf)" >/etc/postgresql/pg_hba.conf
		run_sql -c "select pg_reload_conf();"
	fi

	TMP_CONFIG="/tmp/pg_upgrade/postgresql.conf"
	cp "$POSTGRES_CONFIG_PATH" "$TMP_CONFIG"

	# Check if max_slot_wal_keep_size exists in the config
	# Add the setting if not found
	echo "max_slot_wal_keep_size = -1" >>"$TMP_CONFIG"

	# Remove db_user_namespace if upgrading from PG15 or lower to PG16+
	if [[ ${OLD_PGVERSION%%.*} -le 15 && ${PGVERSION%%.*} -ge 16 ]]; then
		sed -i '/^db_user_namespace/d' "$TMP_CONFIG"
	fi

	chown postgres:postgres "$TMP_CONFIG"

	UPGRADE_COMMAND=$(
		cat <<EOF
    time ${PGBINNEW}/pg_upgrade \
    --old-bindir="${PGBINOLD}" \
    --new-bindir=${PGBINNEW} \
    --old-datadir=${PGDATAOLD} \
    --new-datadir=${PGDATANEW} \
    --username=supabase_admin \
    --jobs="${WORKERS}" -k -r \
    --old-options="-c config_file=$TMP_CONFIG" \
    --old-options="-c shared_preload_libraries='${SHARED_PRELOAD_LIBRARIES}'" \
    --new-options="-c data_directory=${PGDATANEW}" \
    --new-options="-c config_file=$TMP_CONFIG" \
    --new-options="-c shared_preload_libraries='${SHARED_PRELOAD_LIBRARIES}'"
EOF
	)

	if [ "$IS_NIX_BASED_SYSTEM" = "true" ]; then
		UPGRADE_COMMAND=". /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh && $UPGRADE_COMMAND"
	fi

	if [[ ${PGVERSION%%.*} -ge 16 ]]; then
		GRN_PLUGINS_DIR=/var/lib/postgresql/.nix-profile/lib/groonga/plugins LC_ALL=en_US.UTF-8 LANGUAGE=en_US.UTF-8 LANG=en_US.UTF-8 LOCALE_ARCHIVE=/usr/lib/locale/locale-archive su -pc "$UPGRADE_COMMAND --check" -s "$SHELL" postgres
	else
		GRN_PLUGINS_DIR=/var/lib/postgresql/.nix-profile/lib/groonga/plugins LC_ALL=en_US.UTF-8 LC_CTYPE=$SERVER_LC_CTYPE LC_COLLATE=$SERVER_LC_COLLATE LANGUAGE=en_US.UTF-8 LANG=en_US.UTF-8 LOCALE_ARCHIVE=/usr/lib/locale/locale-archive su -pc "$UPGRADE_COMMAND --check" -s "$SHELL" postgres
	fi

	log "10. Stopping postgres; running pg_upgrade"
	# Extra work to ensure postgres is actually stopped
	#  Mostly needed for PG12 projects with odd systemd unit behavior
	if [ -z "$IS_CI" ]; then
		retry 5 systemctl restart postgresql
		systemctl disable postgresql
		retry 5 systemctl stop postgresql

		sleep 3
		systemctl stop postgresql

	else
		CI_stop_postgres
	fi

	LINK_STARTED=true
	# Start the old PostgreSQL instance with version-specific options
	if [[ ${PGVERSION%%.*} -ge 16 ]]; then
		GRN_PLUGINS_DIR=/var/lib/postgresql/.nix-profile/lib/groonga/plugins LC_ALL=en_US.UTF-8 LANGUAGE=en_US.UTF-8 LANG=en_US.UTF-8 LOCALE_ARCHIVE=/usr/lib/locale/locale-archive su -pc "$UPGRADE_COMMAND" -s "$SHELL" postgres
	else
		GRN_PLUGINS_DIR=/var/lib/postgresql/.nix-profile/lib/groonga/plugins LC_ALL=en_US.UTF-8 LC_CTYPE=$SERVER_LC_CTYPE LC_COLLATE=$SERVER_LC_COLLATE LANGUAGE=en_US.UTF-8 LANG=en_US.UTF-8 LOCALE_ARCHIVE=/usr/lib/locale/locale-archive su -pc "$UPGRADE_COMMAND" -s "$SHELL" postgres
	fi

	# The new cluster takes the old one's place on the volume; complete.sh removes pgdata_old on
	# the new instance once it is up
	log "10.1. Swapping the new cluster into $PGDATAOLD_REAL"
	mv "$PGDATAOLD_REAL" "$DATA_ROOT/pgdata_old"
	mv "$PGDATANEW" "$PGDATAOLD_REAL"

	# copying custom configurations
	log "11. Copying custom configurations"
	# Stale from the volume's last copy-mode upgrade, when it was the migration target
	rm -rf "$DATA_ROOT/conf" "$DATA_ROOT/sql"
	mkdir -p "$DATA_ROOT/conf"
	cp -R /etc/postgresql-custom/* "$DATA_ROOT/conf/"
	# removing supautils config as to allow the latest one provided by the latest image to be used
	rm -f "$DATA_ROOT/conf/supautils.conf" || true
	rm -rf "$DATA_ROOT/conf/extension-custom-scripts" || true

	# removing wal-g config as to allow it to be explicitly enabled on the new instance
	rm -f "$DATA_ROOT/conf/wal-g.conf"

	# copy sql files generated by pg_upgrade
	log "12. Copying sql files generated by pg_upgrade"
	mkdir -p "$DATA_ROOT/sql"
	cp /tmp/pg_upgrade/*.sql "$DATA_ROOT/sql/" || true
	chown -R postgres:postgres "$DATA_ROOT/sql/"

	log "13. Cleaning up"
	cleanup "complete"
}

trap cleanup ERR

echo "running" >/tmp/pg-upgrade-status
if [ -z "$IS_CI" ] && [ -z "$IS_LOCAL_UPGRADE" ]; then
	initiate_upgrade >>"$LOG_FILE" 2>&1 &
	log "Upgrade initiate job completed"
else
	rm -f /tmp/pg-upgrade-status
	initiate_upgrade
fi
