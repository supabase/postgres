#! /usr/bin/env bash

## This script is run on the newly launched instance which is to be promoted to
## become the primary database instance once the upgrade successfully completes.
## The following commands copy custom PG configs and enable previously disabled
## extensions, containing regtypes referencing system OIDs.

set -eEuo pipefail

SCRIPT_DIR=$(dirname -- "$0";)
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

LOG_FILE="/tmp/pg-upgrade-complete.log"

function cleanup {
    UPGRADE_STATUS=${1:-"failed"}
    EXIT_CODE=${?:-0}

    echo "$UPGRADE_STATUS" > /tmp/pg-upgrade-status

    ship_logs "$LOG_FILE" || true

    exit "$EXIT_CODE"
}

function complete_pg_upgrade {
    if [ -f /tmp/pg-upgrade-status ]; then
        echo "Upgrade job already started. Bailing."
        exit 0
    fi

    echo "running" > /tmp/pg-upgrade-status

    echo "1. Mounting data disk"
    if [ -z "$IS_CI" ]; then
        retry 3 mount -a -v
    else
        echo "Skipping mount -a -v"
    fi

    # copying custom configurations
    echo "2. Copying custom configurations"
    retry 3 copy_configs

    echo "3. Starting postgresql"
    if [ -z "$IS_CI" ]; then
        retry 3 start_postgres
    else
        start_postgres --new-bin
    fi

    echo "4. Running generated SQL files"
    retry 3 run_generated_sql

    sleep 5

    echo "5. Restarting postgresql"
    retry 3 stop_postgres || true
    retry 3 start_postgres

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

function start_vacuum_analyze {
    echo "complete" > /tmp/pg-upgrade-status
    su -c 'vacuumdb --all --analyze-in-stages' -s "$SHELL" postgres
    echo "Upgrade job completed"
}

trap cleanup ERR

if [ -z "$IS_CI" ]; then
    complete_pg_upgrade >> $LOG_FILE 2>&1 &
else 
    stop_postgres || true

    rm -f /tmp/pg-upgrade-status
    mv /data_migration /data

    rm -rf /var/lib/postgresql/data
    ln -s /data/pgdata /var/lib/postgresql/data

    complete_pg_upgrade
fi
