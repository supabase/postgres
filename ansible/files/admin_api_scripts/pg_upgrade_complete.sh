#! /usr/bin/env bash

## This script is run on the newly launched instance which is to be promoted to
## become the primary database instance once the upgrade successfully completes.
## The following commands copy custom PG configs and enable previously disabled
## extensions, containing regtypes referencing system OIDs.

set -eEuo pipefail

run_sql() {
    psql -h localhost -U supabase_admin -d postgres "$@"
}

cleanup() {
    UPGRADE_STATUS=${1:-"failed"}
    EXIT_CODE=${?:-0}

    echo "${UPGRADE_STATUS}" > /tmp/pg-upgrade-status

    exit $EXIT_CODE
}

function complete_pg_upgrade {
    if [ -f /tmp/pg-upgrade-status ]; then
        echo "Upgrade job already started. Bailing."
        exit 0
    fi

    echo "running" > /tmp/pg-upgrade-status

    echo "1. Mounting data disk"
    mount -a -v

    # copying custom configurations
    echo "2. Copying custom configurations"
    cp -R /data/conf/* /etc/postgresql-custom/
    chown -R postgres:postgres /var/lib/postgresql/data
    chown -R postgres:postgres /data/pgdata

    echo "3. Starting postgresql"
    service postgresql start

    echo "4. Running generated SQL files"
    if [ -d /data/sql ]; then
        for FILE in /data/sql/*.sql; do
            if [ -f "$FILE" ]; then
                run_sql -f $FILE
            fi
        done
    fi

    sleep 5

    echo "5. Restarting postgresql"
    service postgresql restart

    echo "6. Starting vacuum analyze"
    start_vacuum_analyze

    echo "Upgrade job completed"
}

function start_vacuum_analyze {
    su -c 'vacuumdb --all --analyze-in-stages' -s $SHELL postgres
    cleanup "complete"
}

trap cleanup ERR

complete_pg_upgrade >>/var/log/pg-upgrade-complete.log 2>&1 &
