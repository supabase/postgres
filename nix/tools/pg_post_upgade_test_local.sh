#! /usr/bin/env bash

export PGUSER=supabase_admin
export container=pg_upgrade_test
export PGDATABASE=postgres
export PGHOST=localhost
export PGPORT=50432
export PGPASSWORD=postgres


pg_prove ../../tests/pg_upgrade/tests/01-schema.sql
pg_prove ../../tests/pg_upgrade/tests/02-data.sql
pg_prove ../../tests/pg_upgrade/tests/03-settings.sql
