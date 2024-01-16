#! /usr/bin/env bash

## This script is run on the newly launched instance which is to be promoted to
## become the primary database instance once the upgrade successfully completes.
## The following commands copy custom PG configs and enable previously disabled
## extensions, containing regtypes referencing system OIDs.

set -eEuo pipefail

SCRIPT_DIR=$(dirname -- "$0";)
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

LOG_FILE="/var/log/pg-upgrade-complete.log"

function cleanup {
    UPGRADE_STATUS=${1:-"failed"}
    EXIT_CODE=${?:-0}

    echo "$UPGRADE_STATUS" > /tmp/pg-upgrade-status

    ship_logs "$LOG_FILE" || true

    exit "$EXIT_CODE"
}

function execute_patches {
    # Patching pg_cron ownership as it resets during upgrade
    RESULT=$(run_sql -A -t -c "select count(*) > 0 as pg_is_owner from pg_extension where extname = 'pg_cron' and extowner::regrole::text = 'postgres';")

    if [ "$RESULT" = "t" ]; then
        QUERY=$(cat <<EOF
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

        run_sql -c "$QUERY"
    fi
}

function complete_pg_upgrade {
    if [ -f /tmp/pg-upgrade-status ]; then
        echo "Upgrade job already started. Bailing."
        exit 0
    fi

    echo "running" > /tmp/pg-upgrade-status

    echo "1. Mounting data disk"
    retry 3 mount -a -v

    # copying custom configurations
    echo "2. Copying custom configurations"
    retry 3 copy_configs

    echo "3. Starting postgresql"
    retry 3 service postgresql start

    echo "4. Running generated SQL files"
    retry 3 run_generated_sql

    echo "4.1. Applying patches"
    execute_patches || true

    run_sql -c "ALTER USER postgres WITH NOSUPERUSER;"

    echo "4.2. Applying authentication scheme updates"
    retry 3 apply_auth_scheme_updates

    sleep 5

    echo "5. Restarting postgresql"
    retry 3 service postgresql restart

    echo "5.1. Restarting gotrue and postgrest"
    retry 3 service gotrue restart
    retry 3 service postgrest restart

    echo "6. Starting vacuum analyze"
    retry 3 start_vacuum_analyze
}

function copy_configs {
    cp -R /data/conf/* /etc/postgresql-custom/
    chown -R postgres:postgres /var/lib/postgresql/data
    chown -R postgres:postgres /data/pgdata
}

function run_generated_sql {
    if [ -d /data/sql ]; then
        for FILE in /data/sql/*.sql; do
            if [ -f "$FILE" ]; then
                run_sql -f "$FILE"
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
        run_sql -f /etc/postgresql.schema.sql
    fi
}

function start_vacuum_analyze {
    echo "complete" > /tmp/pg-upgrade-status
    su -c 'vacuumdb --all --analyze-in-stages' -s "$SHELL" postgres
    echo "Upgrade job completed"
}

trap cleanup ERR


complete_pg_upgrade >> $LOG_FILE 2>&1 &
