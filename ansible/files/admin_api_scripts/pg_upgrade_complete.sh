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

set -euo pipefail

run_sql() {
    STATEMENT=$1
    psql -h localhost -U supabase_admin -d postgres -c "$STATEMENT"
}

cleanup() {
    UPGRADE_STATUS=${1:-"failed"}
    EXIT_CODE=${?:-0}

    echo "${UPGRADE_STATUS}" > /tmp/pg-upgrade-status

    exit $EXIT_CODE
}

function complete_pg_upgrade {
    echo "running" > /tmp/pg-upgrade-status

    mount -a -v

    # copying custom configurations
    cp -R /data/conf/* /etc/postgresql-custom/

    service postgresql start

    for EXTENSION in "${EXTENSIONS_TO_REENABLE[@]}"; do
        run_sql "CREATE EXTENSION IF NOT EXISTS ${EXTENSION} CASCADE;"
    done

    sleep 5
    service postgresql restart

    if [[ $(systemctl is-active gotrue) == "inactive" ]]; then
        echo "starting gotrue"
        systemctl start --no-block gotrue || true
    fi

    if [[ $(systemctl is-active postgrest) == "inactive" ]]; then
        echo "starting postgrest"
        systemctl start --no-block postgrest || true
    fi

    echo "Upgrade job completed"
    echo "complete" > /tmp/pg-upgrade-status
}

function start_vacuum_analyze {
    su -c 'vacuumdb --all --analyze-in-stages' -s $SHELL postgres
    cleanup "complete"
}

trap cleanup ERR

complete_pg_upgrade >>/var/log/pg-upgrade-complete.log 2>&1
start_vacuum_analyze >>/var/log/pg-upgrade-complete.log 2>&1 &
