#! /usr/bin/env bash

set -euo pipefail

PGPASSWORD=$1

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

if [ ! -b /dev/nvme2n1 ] ; then
    echo "The block device at /dev/nvme2n1 is not mounted to system; exiting."
    exit 1
fi

trap cleanup ERR

mkdir -p $MOUNT_POINT
mount /dev/nvme2n1 $MOUNT_POINT

run_sql "DROP EXTENSION IF EXISTS pg_graphql;"
run_sql "ALTER USER postgres WITH SUPERUSER;"

rm -rf $MOUNT_POINT/pgdata/*
su -c "/data/bin/initdb -D $MOUNT_POINT/pgdata/" -s $SHELL postgres

PGDATAOLD=$(cat /etc/postgresql/postgresql.conf | grep data_directory | sed "s/data_directory = '\(.*\)'.*/\1/");
PGDATANEW="$MOUNT_POINT/pgdata"
PGBINNEW="$MOUNT_POINT/bin"

# running upgrade using at least 1 cpu core
WORKERS=$(nproc | awk '{ print ($1 == 1 ? 1 : $1 - 1) }')

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