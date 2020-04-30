#!/bin/bash
set -e

echo "host replication $POSTGRES_USER 0.0.0.0/0 trust" >> $PGDATA/pg_hba.conf
echo "shared_preload_libraries = 'pg_stat_statements'" >> $PGDATA/postgresql.conf
echo "pg_stat_statements.max = 10000" >> $PGDATA/postgresql.conf
echo "pg_stat_statements.track = all" >> $PGDATA/postgresql.conf
echo "wal_level=logical" >> $PGDATA/postgresql.conf