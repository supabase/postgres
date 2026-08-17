#! /usr/bin/env bash

## This script is run on the newly launched instance which is to be promoted to
## become the primary database instance once the upgrade successfully completes.
## The following commands copy custom PG configs and enable previously disabled
## extensions, containing regtypes referencing system OIDs.

set -eEuo pipefail

SCRIPT_DIR=$(dirname -- "$0")
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

IS_CI=${IS_CI:-}
LOG_FILE="/var/log/pg-upgrade-complete.log"

# Wait for the volume mapped to /data to appear before attempting to mount it
function wait_for_data_device {
	local fstab_src dev=""
	fstab_src=$(awk '$2 == "/data" {print $1}' /etc/fstab)
	if [ -z "$fstab_src" ]; then
		log "No /data entry in /etc/fstab"
		return 1
	fi

	log "Waiting for /data device ($fstab_src) to appear"
	for _ in $(seq 1 60); do
		dev=$(findfs "$fstab_src" 2>/dev/null) || dev=""
		if [ -n "$dev" ] && [ -b "$dev" ]; then
			log "/data device ($dev) is available"
			return 0
		fi
		sleep 1
	done
	log "Timed out waiting for /data device ($fstab_src)"
	return 1
}

function cleanup {
	UPGRADE_STATUS=${1:-"failed"}
	EXIT_CODE=${?:-0}

	echo "$UPGRADE_STATUS" >/tmp/pg-upgrade-status

	ship_logs "$LOG_FILE" || true

	exit "$EXIT_CODE"
}

function execute_extension_upgrade_patches {
	if [ -f "/var/lib/postgresql/extension/wrappers--0.3.1--0.4.1.sql" ] && [ ! -f "/usr/share/postgresql/15/extension/wrappers--0.3.0--0.4.1.sql" ]; then
		cp /var/lib/postgresql/extension/wrappers--0.3.1--0.4.1.sql /var/lib/postgresql/extension/wrappers--0.3.0--0.4.1.sql
		ln -s /var/lib/postgresql/extension/wrappers--0.3.0--0.4.1.sql /usr/share/postgresql/15/extension/wrappers--0.3.0--0.4.1.sql
	fi
}

function execute_wrappers_patch {
	# If upgrading to pgsodium-less Vault, Wrappers need to be updated so that
	# foreign servers use `vault.secrets.id` instead of `vault.secrets.key_id`
	UPDATE_WRAPPERS_SERVER_OPTIONS_QUERY=$(
		cat <<EOF
  DO \$\$
  DECLARE
    server_rec RECORD;
    option_rec RECORD;
    vault_secrets RECORD;
  BEGIN
    IF EXISTS (SELECT FROM pg_extension WHERE extname = 'wrappers')
      AND EXISTS (SELECT FROM pg_extension WHERE extname = 'supabase_vault')
      AND EXISTS (SELECT FROM pg_available_extension_versions WHERE name = 'wrappers' AND version NOT IN (
      '0.1.0',
      '0.1.1',
      '0.1.4',
      '0.1.5',
      '0.1.6',
      '0.1.7',
      '0.1.8',
      '0.1.9',
      '0.1.10',
      '0.1.11',
      '0.1.12',
      '0.1.14',
      '0.1.15',
      '0.1.16',
      '0.1.17',
      '0.1.18',
      '0.1.19',
      '0.2.0',
      '0.3.0',
      '0.3.1',
      '0.4.0',
      '0.4.1',
      '0.4.2',
      '0.4.3',
      '0.4.4',
      '0.4.5'
    ))
    THEN
      FOR server_rec IN
        SELECT srvname, srvoptions
        FROM pg_foreign_server
      LOOP
        FOR option_rec IN
          SELECT split_part(srvoption, '=', 1) AS option_name, split_part(srvoption, '=', 2) AS option_value
          FROM UNNEST(server_rec.srvoptions) AS srvoption
        LOOP
          IF EXISTS (SELECT FROM vault.secrets WHERE option_rec.option_value IN (id::text, key_id::text)) THEN
            EXECUTE format(
              'ALTER SERVER %I OPTIONS (SET %I %L)',
              server_rec.srvname,
              option_rec.option_name,
              (SELECT id FROM vault.secrets WHERE option_rec.option_value IN (id::text, key_id::text))
            );
          END IF;
        END LOOP;
      END LOOP;
    END IF;
  END;
  \$\$;
EOF
	)
	run_sql -c "$UPDATE_WRAPPERS_SERVER_OPTIONS_QUERY"
}

function execute_patches {
	# Patch pg_net grants
	PG_NET_ENABLED=$(run_sql -A -t -c "select count(*) > 0 from pg_extension where extname = 'pg_net';")

	if [ "$PG_NET_ENABLED" = "t" ]; then
		PG_NET_GRANT_QUERY=$(
			cat <<EOF
        GRANT USAGE ON SCHEMA net TO supabase_functions_admin, postgres, anon, authenticated, service_role;

        ALTER function net.http_get(url text, params jsonb, headers jsonb, timeout_milliseconds integer) SECURITY DEFINER;
        ALTER function net.http_post(url text, body jsonb, params jsonb, headers jsonb, timeout_milliseconds integer) SECURITY DEFINER;

        ALTER function net.http_get(url text, params jsonb, headers jsonb, timeout_milliseconds integer) SET search_path = net;
        ALTER function net.http_post(url text, body jsonb, params jsonb, headers jsonb, timeout_milliseconds integer) SET search_path = net;

        REVOKE ALL ON FUNCTION net.http_get(url text, params jsonb, headers jsonb, timeout_milliseconds integer) FROM PUBLIC;
        REVOKE ALL ON FUNCTION net.http_post(url text, body jsonb, params jsonb, headers jsonb, timeout_milliseconds integer) FROM PUBLIC;

        GRANT EXECUTE ON FUNCTION net.http_get(url text, params jsonb, headers jsonb, timeout_milliseconds integer) TO supabase_functions_admin, postgres, anon, authenticated, service_role;
        GRANT EXECUTE ON FUNCTION net.http_post(url text, body jsonb, params jsonb, headers jsonb, timeout_milliseconds integer) TO supabase_functions_admin, postgres, anon, authenticated, service_role;
EOF
		)

		run_sql -c "$PG_NET_GRANT_QUERY"
	fi

	# Patching pg_cron ownership as it resets during upgrade
	HAS_PG_CRON_OWNED_BY_POSTGRES=$(run_sql -A -t -c "select count(*) > 0 from pg_extension where extname = 'pg_cron' and extowner::regrole::text = 'postgres';")

	if [ "$HAS_PG_CRON_OWNED_BY_POSTGRES" = "t" ]; then
		RECREATE_PG_CRON_QUERY=$(
			cat <<EOF
        begin;
        create temporary table cron_job as select * from cron.job;
        create temporary table cron_job_run_details as select * from cron.job_run_details;
        drop extension pg_cron;
        create extension pg_cron schema pg_catalog;
        insert into cron.job select * from cron_job;
        insert into cron.job_run_details select * from cron_job_run_details;
        select setval('cron.jobid_seq', coalesce(max(jobid), 0) + 1, false) from cron.job;
        select setval('cron.runid_seq', coalesce(max(runid), 0) + 1, false) from cron.job_run_details;
        update cron.job set username = 'postgres' where username = 'supabase_admin';
        commit;
EOF
		)

		run_sql -c "$RECREATE_PG_CRON_QUERY"
	fi

	# Patching pgmq ownership as it resets during upgrade
	HAS_PGMQ=$(run_sql -A -t -c "select count(*) > 0 from pg_extension where extname = 'pgmq';")
	if [ "$HAS_PGMQ" = "t" ]; then
		run_sql -c "update pg_extension set extowner = 'postgres'::regrole where extname = 'pgmq';"
	fi

	# Patch to handle upgrading to pgsodium-less Vault
	REENCRYPT_VAULT_SECRETS_QUERY=$(
		cat <<EOF
    DO \$\$
    BEGIN
      IF EXISTS (SELECT FROM pg_available_extension_versions WHERE name = 'supabase_vault' AND version = '0.3.0')
        AND EXISTS (SELECT FROM pg_extension WHERE extname = 'supabase_vault')
      THEN
        IF (SELECT extversion FROM pg_extension WHERE extname = 'supabase_vault') != '0.2.8' THEN
          grant usage on schema vault to postgres with grant option;
          grant select, delete, truncate, references on vault.secrets, vault.decrypted_secrets to postgres with grant option;
          grant execute on function vault.create_secret, vault.update_secret, vault._crypto_aead_det_decrypt to postgres with grant option;

          -- service_role used to be able to manage secrets in Vault <=0.2.8 because it had privileges to pgsodium functions
          grant usage on schema vault to service_role;
          grant select, delete on vault.secrets, vault.decrypted_secrets to service_role;
          grant execute on function vault.create_secret, vault.update_secret, vault._crypto_aead_det_decrypt to service_role;
        END IF;
        -- Do an explicit IF EXISTS check to avoid referencing pgsodium objects if the project already migrated away from using pgsodium.
        IF EXISTS (SELECT FROM vault.secrets WHERE key_id IS NOT NULL) THEN
          UPDATE vault.secrets s
          SET
            secret = encode(
              vault._crypto_aead_det_encrypt(
                message := pgsodium.crypto_aead_det_decrypt(decode(s.secret, 'base64'), convert_to(s.id || s.description || s.created_at || s.updated_at, 'utf8'), s.key_id, s.nonce),
                additional := convert_to(s.id::text, 'utf8'),
                key_id := 0,
                context := 'pgsodium'::bytea,
                nonce := s.nonce
              ),
              'base64'
            ),
            key_id = NULL
          WHERE
            key_id IS NOT NULL;
        END IF;
      END IF;
    END
    \$\$;
EOF
	)
	run_sql -c "$REENCRYPT_VAULT_SECRETS_QUERY"

	GRANT_PREDEFINED_ROLES_TO_POSTGRES_QUERY=$(
		cat <<EOF
    DO \$\$
    DECLARE
      major_version INT;
    BEGIN
      SELECT current_setting('server_version_num')::INT / 10000 INTO major_version;
      IF major_version >= 16 THEN
        GRANT pg_create_subscription TO postgres;
        GRANT anon, authenticated, service_role, authenticator, pg_monitor, pg_read_all_data, pg_signal_backend TO postgres WITH ADMIN OPTION;
      END IF;
      GRANT pg_monitor, pg_read_all_data, pg_signal_backend TO postgres;
    END
    \$\$;
EOF
	)
	run_sql -c "$GRANT_PREDEFINED_ROLES_TO_POSTGRES_QUERY"
}

function complete_pg_upgrade {
	if [ -f /tmp/pg-upgrade-status ]; then
		log "Upgrade job already started. Bailing."
		exit 0
	fi

	echo "running" >/tmp/pg-upgrade-status

	# Set (including from called functions, via dynamic scoping) whenever a fail-soft step failed; ships the log for visibility at the end
	local warnings=0

	log "1. Mounting data disk"
	if [ -z "$IS_CI" ]; then
		# Let udev finish detecting the vollume before mounting
		udevadm settle --timeout=60 || true
		wait_for_data_device

		retry 8 mount -a -v

		# `nofail` in /etc/fstab makes `mount -a` exit with a code of 0 even when the volume is absent
		# In the offchance of the volume not being mounted or detected, explicitly fail here
		if ! mountpoint -q /data; then
			log "FATAL: /data is not a mountpoint"
			exit 1
		fi
	else
		log "Skipping mount -a -v"
	fi

	# copying custom configurations
	log "2. Copying custom configurations"
	retry 3 copy_configs

	log "3. Starting postgresql"
	if [ -z "$IS_CI" ]; then
		retry 3 service postgresql start
		retry 8 pg_isready -h localhost -p 5432 -U supabase_admin
	else
		CI_start_postgres --new-bin
	fi

	execute_extension_upgrade_patches || {
		log "WARNING: extension upgrade patches failed"
		warnings=1
	}

	# For this to work we need `vault.secrets` from the old project to be
	# preserved, but `run_generated_sql` includes `ALTER EXTENSION
	# supabase_vault UPDATE` which modifies that. So we need to run it
	# beforehand.
	log "3.1. Patch Wrappers server options"
	execute_wrappers_patch

	log "4. Running generated SQL files"
	# Deliberately fail-soft per file (a failed ALTER EXTENSION UPDATE shouldn't fail the upgrade) so it never returns non-zero — a retry wrapper here would be dead code, and re-running would make already-applied updates error spuriously
	run_generated_sql

	log "4.1. Applying patches"
	execute_patches || {
		log "WARNING: post-upgrade patches failed"
		warnings=1
	}

	run_sql -c "ALTER USER postgres WITH NOSUPERUSER;"

	log "4.2. Applying authentication scheme updates"
	retry 3 apply_auth_scheme_updates

	sleep 5

	log "5. Restarting postgresql"
	if [ -z "$IS_CI" ]; then
		retry 3 service postgresql restart
		retry 8 pg_isready -h localhost -p 5432 -U supabase_admin

		log "5.1. Restarting gotrue and postgrest"
		retry 3 service gotrue restart
		retry 3 service postgrest restart

	else
		retry 3 CI_stop_postgres || true
		retry 3 CI_start_postgres
	fi

	log "6. Starting vacuum analyze"
	# A failed analyze is not worth failing the whole upgrade for; the status file already reads "complete" and the ERR trap would flip it to "failed"
	retry 3 start_vacuum_analyze || {
		log "WARNING: vacuum analyze failed after retries"
		warnings=1
	}

	log "6.1. Analyzing partitioned tables"
	# vacuumdb skips partitioned parents (fixed upstream only in PG19) and autovacuum never analyzes them, so without this they'd have no stats at all
	retry 3 analyze_partitioned_tables || {
		log "WARNING: partitioned table analyze failed after retries"
		warnings=1
	}

	log "Upgrade job completed"

	# Clean runs ship nothing — only warn-but-completed upgrades are reported (hard failures ship via the ERR-trap cleanup)
	if [ "$warnings" = 1 ]; then
		ship_logs "$LOG_FILE" || true
	fi
}

function copy_configs {
	cp -R /data/conf/* /etc/postgresql-custom/
	chown -R postgres:postgres /var/lib/postgresql/data
	chown -R postgres:postgres /data/pgdata
	chmod -R 0750 /data/pgdata
}

function run_generated_sql {
	if [ -d /data/sql ]; then
		for FILE in /data/sql/*.sql; do
			if [ -f "$FILE" ]; then
				run_sql -f "$FILE" || {
					log "WARNING: generated SQL file $FILE failed"
					warnings=1
				}
			fi
		done
	fi
}

# Projects which had their passwords hashed using md5 need to have their passwords reset
# Passwords for managed roles are already present in /etc/postgresql.schema.sql
function apply_auth_scheme_updates {
	PASSWORD_ENCRYPTION_SETTING=$(run_sql -A -t -c "SHOW password_encryption;")
	if [ "$PASSWORD_ENCRYPTION_SETTING" = "md5" ]; then
		run_sql -c "ALTER SYSTEM SET password_encryption TO 'scram-sha-256';"
		run_sql -c "SELECT pg_reload_conf();"

		if [ -z "$IS_CI" ]; then
			run_sql -f /etc/postgresql.schema.sql
		fi
	fi
}

function start_vacuum_analyze {
	echo "complete" >/tmp/pg-upgrade-status

	# shellcheck disable=SC1091
	if [ -f "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh" ]; then
		# shellcheck disable=SC1091
		source "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"
	fi
	# Conservative parallelism and a cost-delay reset (in case the customer raised it) — traffic may already be live
	local jobs
	jobs=$(($(nproc) / 4))
	if [ "$jobs" -lt 1 ]; then
		jobs=1
	fi
	# --skip-locked rather than a lock_timeout: a lock-timeout error aborts the whole staged all-databases run, and the retry restarts from stage 1 — overwriting finer stats an earlier attempt already wrote with stage 1's coarse target=1. Skipping just the locked table preserves every other table's progress
	PGOPTIONS='-c vacuum_cost_delay=0' vacuumdb --all --analyze-in-stages --skip-locked -j "$jobs" -U supabase_admin -h localhost -p 5432
}

function analyze_partitioned_tables {
	local rc=0 db stmts dbs
	# Capture the list (vs substituting into the for-list) so a failed enumeration can't trip the ERR trap inside the subshell and overwrite the status file
	dbs=$(run_sql -X -p 5432 -A -t -c "select datname from pg_database where datallowconn") || return 1
	# Iterate by line, not by word — datnames can contain spaces and glob characters
	while IFS= read -r db; do
		if [ -z "$db" ]; then
			continue
		fi
		stmts=$(run_sql -X -p 5432 -d "$db" -A -t -c "select format('ANALYZE %I.%I;', n.nspname, c.relname) from pg_class c join pg_namespace n on n.oid = c.relnamespace where c.relkind = 'p' and not exists (select from pg_statistic s where s.starelid = c.oid)") || {
			rc=1
			continue
		}
		if [ -n "$stmts" ]; then
			# The instance is serving traffic by now: fail fast into the retry rather than queue behind a customer lock (autovacuum's ANALYZE cancels itself for us), and cap runaway many-leaf recursion rather than grind against live traffic
			{
				echo "set lock_timeout = '10s';"
				echo "set statement_timeout = '10min';"
				echo "$stmts"
			} | run_sql -X -p 5432 -d "$db" -v ON_ERROR_STOP=1 || rc=1
		fi
	done <<<"$dbs"
	return $rc
}

case $# in
0) ;;
1)
	if ! declare -F "$1" >/dev/null; then
		log "Error: unknown function $1" >&2
		exit 1
	fi
	$1
	exit
	;;
*)
	log "Error: $(basename "$0") takes 0 args or a function to call, got $*" >&2
	exit 1
	;;
esac

trap cleanup ERR

echo "C.UTF-8 UTF-8" >/etc/locale.gen
echo "en_US.UTF-8 UTF-8" >>/etc/locale.gen
locale-gen

if [ -z "$IS_CI" ]; then
	complete_pg_upgrade >>$LOG_FILE 2>&1 &
else
	CI_stop_postgres || true

	rm -f /tmp/pg-upgrade-status
	mv /data_migration /data

	rm -rf /var/lib/postgresql/data
	ln -s /data/pgdata /var/lib/postgresql/data

	complete_pg_upgrade
fi
