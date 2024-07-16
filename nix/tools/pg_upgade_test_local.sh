#! /usr/bin/env bash

export PGUSER=supabase_admin
export container=pg_upgrade_test
export PGDATABASE=postgres
export PGHOST=localhost
export PGPORT=5432
export PGPASSWORD=postgres



docker exec "$container" bash -c "/docker-entrypoint-initdb.d/migrate.sh 2>&1"

pg_prove ../../migrations/tests/test.sql

psql -f "../../tests/pg_upgrade/tests/98-data-fixtures.sql"
psql -f "../../tests/pg_upgrade/tests/99-fixtures.sql"

