#! /usr/bin/env bash

set -euo pipefail

PGVERSION=$1
PGPASSWORD=$2

MOUNT_POINT="/data_migration"

run_sql() {
    STATEMENT=$1
    psql -h localhost -U supabase_admin -d postgres -c "$STATEMENT"
}

cleanup() {
    EXIT_CODE=${?:-0}

    systemctl start postgresql
    run_sql "CREATE EXTENSION IF NOT EXISTS pg_graphql;"
    run_sql "ALTER USER postgres WITH NOSUPERUSER;"

    umount $MOUNT_POINT

    exit $EXIT_CODE
}

function initiate_upgrade {
    BLOCK_DEVICE=$(lsblk -dpno name | grep -v "/dev/nvme[0-1]")

    mkdir -p $MOUNT_POINT
    mount $BLOCK_DEVICE $MOUNT_POINT

    tar zxvf "$MOUNT_POINT/binaries/$PGVERSION.tar.gz" -C "$MOUNT_POINT/binaries"
    chown -R postgres:postgres "$MOUNT_POINT/binaries/$PGVERSION"

    run_sql "DROP EXTENSION IF EXISTS pg_graphql;"
    run_sql "ALTER USER postgres WITH SUPERUSER;"

    PGDATAOLD=$(cat /etc/postgresql/postgresql.conf | grep data_directory | sed "s/data_directory = '\(.*\)'.*/\1/");
    PGDATANEW="$MOUNT_POINT/pgdata"
    PGBINNEW="$MOUNT_POINT/binaries/$PGVERSION/bin"


    rm -rf $PGDATANEW/*
    su -c "$PGBINNEW/initdb -D $PGDATANEW/" -s $SHELL postgres

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

    cleanup
}

trap cleanup ERR

initiate_upgrade >> /var/log/pg-upgrade-initiate.log 2>&1
echo "Upgrade initiate job completed "
