#! /usr/bin/env bash

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
    run_sql "CREATE EXTENSION IF NOT EXISTS pg_graphql;"

    sleep 5
    service postgresql restart
}

set -euo pipefail

complete_pg_upgrade >> /var/log/pg-upgrade-complete.log 2>&1
echo "Upgrade job completed"
