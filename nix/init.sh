#!/bin/bash
# shellcheck shell=bash

export PGUSER=postgres
export PGDATA=$PWD/postgres_data
export PGHOST=$PWD/postgres
export PGPORT=5432
export PGPASS=postgres
export LOG_PATH=$PGHOST/LOG
export PGDATABASE=testdb
export DATABASE_URL="postgresql:///$PGDATABASE?host=$PGHOST&port=$PGPORT"
mkdir -p $PGHOST
if [ ! -d $PGDATA ]; then
    echo 'Initializing postgresql database...'
    initdb $PGDATA --locale=C --username $PGUSER -A md5 --pwfile=<(echo $PGPASS) --auth=trust
    echo "listen_addresses='*'" >> $PGDATA/postgresql.conf
    echo "unix_socket_directories='$PGHOST'" >> $PGDATA/postgresql.conf
    echo "unix_socket_permissions=0700" >> $PGDATA/postgresql.conf
fi
chmod o-rwx $PGDATA
