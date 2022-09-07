#! /usr/bin/env bash

function complete_pg_upgrade {
    mount -a -v

    # copying custom configurations
    cp /data/conf/* /etc/postgresql-custom/

    service postgresql start
    su -c 'vacuumdb --all --analyze-in-stages' -s $SHELL postgres
    su -c 'psql -c "CREATE EXTENSION IF NOT EXISTS pg_graphql;"' -s $SHELL postgres
}

set -euo pipefail

complete_pg_upgrade >> /var/log/pg-upgrade-complete.log 2>&1
echo "Upgrade job completed"
