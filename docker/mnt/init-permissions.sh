#!/bin/bash
set -e

echo "host replication $POSTGRES_USER 0.0.0.0/0 trust" >> $PGDATA/pg_hba.conf
echo "shared_preload_libraries = 'pg_stat_statements, pgaudit'" >> $PGDATA/postgresql.conf
echo "pg_stat_statements.max = 10000" >> $PGDATA/postgresql.conf
echo "pg_stat_statements.track = all" >> $PGDATA/postgresql.conf
echo "wal_level=logical" >> $PGDATA/postgresql.conf
echo "max_replication_slots=5" >> $PGDATA/postgresql.conf
echo "max_wal_senders=10" >> $PGDATA/postgresql.conf
echo "log_destination='csvlog'" >> $PGDATA/postgresql.conf
echo "logging_collector=on" >> $PGDATA/postgresql.conf
echo "log_filename='postgresql.log'" >> $PGDATA/postgresql.conf
echo "log_rotation_age=0" >> $PGDATA/postgresql.conf
echo "log_rotation_size=0" >> $PGDATA/postgresql.conf
echo "pljava.libjvm_location = '/usr/lib/jvm/java-11-openjdk-amd64/lib/server/libjvm.so'" >> $PGDATA/postgresql.conf
