#! /usr/bin/env bash

export PGUSER=supabase_admin
export container=pg_upgrade_test
export PGDATABASE=postgres
export PGHOST=localhost
export PGPORT=5432
export PGPASSWORD=postgres




psql -c "select * from pg_extension;"
psql -c "ALTER SYSTEM SET password_encryption TO 'scram-sha-256';"