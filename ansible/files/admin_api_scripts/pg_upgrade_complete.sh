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


run_sql() {
    STATEMENT=$1
    psql -h localhost -U supabase_admin -d postgres -c "$STATEMENT"
}

function complete_pg_upgrade {
    mount -a -v

    # copying custom configurations
    cp /data/conf/* /etc/postgresql-custom/

    service postgresql start
    su -c 'vacuumdb --all --analyze-in-stages' -s $SHELL postgres

    for EXTENSION in "${EXTENSIONS_TO_REENABLE[@]}"; do
        run_sql "CREATE EXTENSION IF NOT EXISTS ${EXTENSION} CASCADE;"
    done
    
    sleep 5
    service postgresql restart

    sleep 5
    service postgresql restart
}

set -euo pipefail

complete_pg_upgrade >> /var/log/pg-upgrade-complete.log 2>&1
echo "Upgrade job completed"
