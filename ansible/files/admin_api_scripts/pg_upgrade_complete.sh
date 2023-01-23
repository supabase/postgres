#! /usr/bin/env bash

## This script is run on the newly launched instance which is to be promoted to
## become the primary database instance once the upgrade successfully completes.
## The following commands copy custom PG configs and enable previously disabled
## extensions, containing regtypes referencing system OIDs.

# Extensions to be reenabled after pg_upgrade.
# Running an upgrade with these extensions enabled will result in errors due to
# them depending on regtypes referencing system OIDs. Thus they have been disabled
# beforehand.
EXTENSIONS_TO_REENABLE=(
    "pg_graphql"
)

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

    mount -a -v

    # copying custom configurations
    cp -R /data/conf/* /etc/postgresql-custom/
    chown -R postgres:postgres /var/lib/postgresql/data
    chown -R postgres:postgres /data/pgdata

    service postgresql start

    for EXTENSION in "${EXTENSIONS_TO_REENABLE[@]}"; do
        run_sql -c "CREATE EXTENSION IF NOT EXISTS ${EXTENSION} CASCADE;"
    done

    if [ -d /data/sql ]; then
        for FILE in /data/sql/*.sql; do
            run_sql -f $FILE
        done
    fi

    sleep 5
    service postgresql restart

    start_vacuum_analyze

    echo "Upgrade job completed"
}

function start_vacuum_analyze {
    su -c 'vacuumdb --all --analyze-in-stages' -s $SHELL postgres
    cleanup "complete"
}

trap cleanup ERR

complete_pg_upgrade >>/var/log/pg-upgrade-complete.log 2>&1 &
