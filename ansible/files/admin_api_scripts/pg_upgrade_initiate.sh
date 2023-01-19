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

function shutdown_services {
    if [[ $(systemctl is-active gotrue) == "active" ]]; then
        echo "stopping gotrue"
        systemctl stop gotrue || true
    fi

    if [[ $(systemctl is-active postgrest) == "active" ]]; then
        echo "stopping postgrest"
        systemctl stop postgrest || true
    fi
}

function start_services {
    if [[ $(systemctl is-active gotrue) == "inactive" ]]; then
        echo "starting gotrue"
        systemctl start gotrue || true
    fi

    if [[ $(systemctl is-active postgrest) == "inactive" ]]; then
        echo "starting postgrest"
        systemctl start postgrest || true
    fi
}

cleanup() {
    UPGRADE_STATUS=${1:-"failed"}
    EXIT_CODE=${?:-0}

    if [ -d "${MOUNT_POINT}/pgdata/pg_upgrade_output.d/" ]; then
        cp -R "${MOUNT_POINT}/pgdata/pg_upgrade_output.d/" /var/log/
    fi

    if [ -L /var/lib/postgresql ]; then
        rm /var/lib/postgresql
        mv /var/lib/postgresql.bak /var/lib/postgresql
    fi

    systemctl restart postgresql
    sleep 10
    systemctl restart postgresql

    for EXTENSION in "${EXTENSIONS_TO_DISABLE[@]}"; do
        run_sql "CREATE EXTENSION IF NOT EXISTS ${EXTENSION} CASCADE;"
    done

    run_sql "ALTER USER postgres WITH NOSUPERUSER;"

    start_services

    umount $MOUNT_POINT
    echo "${UPGRADE_STATUS}" > /tmp/pg-upgrade-status

    exit $EXIT_CODE
}

function initiate_upgrade {
    echo "running" > /tmp/pg-upgrade-status

    shutdown_services

    # awk NF==3 prints lines with exactly 3 fields, which are the block devices currently not mounted anywhere
    # excluding nvme0 since it is the root disk
    BLOCK_DEVICE=$(lsblk -dprno name,size,mountpoint,type | grep "disk" | grep -v "nvme0" | awk 'NF==3 { print $1; }')

    mkdir -p "$MOUNT_POINT"
    mount "$BLOCK_DEVICE" "$MOUNT_POINT"
    resize2fs "$BLOCK_DEVICE"

    SHARED_PRELOAD_LIBRARIES=$(cat /etc/postgresql/postgresql.conf | grep shared_preload_libraries |  sed "s/shared_preload_libraries = '\(.*\)'.*/\1/")
    PGDATAOLD=$(cat /etc/postgresql/postgresql.conf | grep data_directory | sed "s/data_directory = '\(.*\)'.*/\1/")    

    PGDATANEW="$MOUNT_POINT/pgdata"
    PGBINNEW="/tmp/pg_upgrade_bin/$PGVERSION/bin"
    PGSHARENEW="/tmp/pg_upgrade_bin/$PGVERSION/share"

    mkdir -p "/tmp/pg_upgrade_bin"
    tar zxvf "/tmp/persistent/pg_upgrade_bin.tar.gz" -C "/tmp/pg_upgrade_bin"

    # copy upgrade-specific pgsodium_getkey script into the share dir
    cp /root/pg_upgrade_pgsodium_getkey.sh "$PGSHARENEW/extension/pgsodium_getkey"
    chmod +x "$PGSHARENEW/extension/pgsodium_getkey"

    if [ -f "$MOUNT_POINT/pgsodium_root.key" ]; then
        cp "$MOUNT_POINT/pgsodium_root.key" /etc/postgresql-custom/pgsodium_root.key
        chown postgres:postgres /etc/postgresql-custom/pgsodium_root.key
        chmod 600 /etc/postgresql-custom/pgsodium_root.key
    fi

    chown -R postgres:postgres "/tmp/pg_upgrade_bin/$PGVERSION"

    for EXTENSION in "${EXTENSIONS_TO_DISABLE[@]}"; do
        run_sql "DROP EXTENSION IF EXISTS ${EXTENSION} CASCADE;"
    done

    run_sql "ALTER USER postgres WITH SUPERUSER;"


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
    --new-options="-c data_directory=${PGDATANEW}" \
    --new-options="-c shared_preload_libraries='${SHARED_PRELOAD_LIBRARIES}'"
EOF
    )

    mv /var/lib/postgresql /var/lib/postgresql.bak
    ln -s /tmp/pg_upgrade_bin/15/share /var/lib/postgresql

    if [ ! -L /var/lib/postgresql.bak/data ]; then
        ln -s /var/lib/postgresql.bak/data /var/lib/postgresql/data
    fi

    systemctl stop postgresql
    su -c "$UPGRADE_COMMAND" -s $SHELL postgres

    # copying custom configurations
    mkdir -p $MOUNT_POINT/conf
    cp -R /etc/postgresql-custom/* $MOUNT_POINT/conf/

    cleanup "complete"
}

trap cleanup ERR

initiate_upgrade >> /var/log/pg-upgrade-initiate.log 2>&1 &
echo "Upgrade initiate job completed"
