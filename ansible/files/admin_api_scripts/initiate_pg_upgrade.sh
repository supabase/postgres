#! /usr/bin/env bash

set -euo pipefail

rm -rf /data/pgdata/* && /data/bin/initdb -D /data_migration/pgdata/

PGDATAOLD=$(cat /etc/postgresql/postgresql.conf | grep data_directory | sed "s/data_directory = '\(.*\)'.*/\1/");
PGDATANEW="/data/pgdata"
PGBINNEW="/data/bin"

#TODO: handle case when single CPU core
WORKERS=$(($(nproc) - 1))

time ${PGBINNEW}/pg_upgrade \
--old-bindir="/usr/lib/postgresql/bin" \
--new-bindir=${PGBINNEW} \
--old-datadir=${PGDATAOLD} \
--new-datadir=${PGDATANEW} \
--jobs="${WORKERS}" \
--old-options='-c config_file=/etc/postgresql/postgresql.conf' \
--new-options="-c data_directory=${PGDATANEW}"