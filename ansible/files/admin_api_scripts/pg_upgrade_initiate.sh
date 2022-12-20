#! /usr/bin/env bash

## This script is run on the old (source) instance, mounting the data disk
## of the newly launched instance, disabling extensions containing regtypes,
## and running pg_upgrade.
## It reports the current status of the upgrade process to /tmp/pg-upgrade-status,
## which can then be subsequently checked through pg_upgrade_check.sh.

# Extensions to disable before running pg_upgrade.
# Running an upgrade with these extensions enabled will result in errors due to 
# them depending on regtypes referencing system OIDs. 
EXTENSIONS_TO_DISABLE=(
    "pg_graphql"
)

set -eEuo pipefail

PGVERSION=$1

MOUNT_POINT="/data_migration"

run_sql() {
    STATEMENT=$1
    psql -h localhost -U supabase_admin -d postgres -c "$STATEMENT"
}

cleanup() {
    UPGRADE_STATUS=${1:-"failed"}
    EXIT_CODE=${?:-0}

    systemctl start postgresql
    
    for EXTENSION in "${EXTENSIONS_TO_DISABLE[@]}"; do
        run_sql "CREATE EXTENSION IF NOT EXISTS ${EXTENSION} CASCADE;"
    done

    run_sql "ALTER USER postgres WITH NOSUPERUSER;"

    umount $MOUNT_POINT
    echo "${UPGRADE_STATUS}" > /tmp/pg-upgrade-status

    exit $EXIT_CODE
}

function initiate_upgrade {
    BLOCK_DEVICE=$(lsblk -dpno name | grep -v "/dev/nvme[0-1]")
    echo "running" > /tmp/pg-upgrade-status

    mkdir -p "$MOUNT_POINT"
    mount "$BLOCK_DEVICE" "$MOUNT_POINT"

    mkdir -p "/tmp/pg_upgrade_bin"
    tar zxvf "/tmp/persistent/pg_upgrade_bin.tar.gz" -C "/tmp/pg_upgrade_bin"
    chown -R postgres:postgres "/tmp/pg_upgrade_bin/$PGVERSION"

    for EXTENSION in "${EXTENSIONS_TO_DISABLE[@]}"; do
        run_sql "DROP EXTENSION IF EXISTS ${EXTENSION} CASCADE;"
    done

    run_sql "ALTER USER postgres WITH SUPERUSER;"

    PGDATAOLD=$(cat /etc/postgresql/postgresql.conf | grep data_directory | sed "s/data_directory = '\(.*\)'.*/\1/");
    PGDATANEW="$MOUNT_POINT/pgdata"
    PGBINNEW="/tmp/pg_upgrade_bin/$PGVERSION/bin"
    PGSHARENEW="/tmp/pg_upgrade_bin/$PGVERSION/share"

    chown -R postgres:postgres "$MOUNT_POINT/"
    rm -rf "$PGDATANEW/"
    su -c "$PGBINNEW/initdb -L $PGSHARENEW -D $PGDATANEW/" -s $SHELL postgres

    # running upgrade using at least 1 cpu core
    WORKERS=$(nproc | awk '{ print ($1 == 1 ? 1 : $1 - 1) }')

    # upgrade job outputs a log in the cwd; needs write permissions
    cd /tmp

    UPGRADE_COMMAND=$(cat <<EOF
    time ${PGBINNEW}/pg_upgrade \
    --old-bindir="/usr/lib/postgresql/bin" \
    --new-bindir=${PGBINNEW} \
    --old-datadir=${PGDATAOLD} \
    --new-datadir=${PGDATANEW} \
    --jobs="${WORKERS}" \
    --old-options='-c config_file=/etc/postgresql/postgresql.conf' \
    --new-options="-c data_directory=${PGDATANEW}"
EOF
    )

    systemctl stop postgresql
    su -c "$UPGRADE_COMMAND" -s $SHELL postgres

    # copying custom configurations
    mkdir -p $MOUNT_POINT/conf
    cp /etc/postgresql-custom/* $MOUNT_POINT/conf/

    cleanup "complete"
}

trap cleanup ERR

initiate_upgrade >> /var/log/pg-upgrade-initiate.log 2>&1
echo "Upgrade initiate job completed "
