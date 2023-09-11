#!/bin/bash

set -eEuo pipefail

export PGPASSWORD=postgres
export PGUSER=supabase_admin
export PGHOST=localhost
export PGDATABASE=postgres

INITIAL_PG_VERSION=$1
docker rm -f pg_upgrade_test || true
trap "docker rm -f pg_upgrade_test || true" EXIT SIGINT SIGTERM ERR

docker run -t --name pg_upgrade_test --env-file .env \
   -v "$(pwd)/scripts:/tmp/upgrade" \
   --entrypoint /tmp/upgrade/entrypoint.sh -d \
   -p 5432:5432 \
   "supabase/postgres:${INITIAL_PG_VERSION}"

sleep 3
while ! docker exec -it pg_upgrade_test bash -c "pg_isready"; do
  echo "Waiting for postgres to start..."
  sleep 1
done

echo "Running migrations"
docker exec -it pg_upgrade_test bash -c "/docker-entrypoint-initdb.d/migrate.sh > /tmp/migrate.log 2>&1"

echo "Running tests"
pg_prove "../../migrations/tests/test.sql"
psql -f "./tests/98-data-fixtures.sql"
psql -f "./tests/99-fixtures.sql"

echo "Initiating pg_upgrade"
docker exec -it pg_upgrade_test bash -c '/tmp/upgrade/pg_upgrade_scripts/initiate.sh "$PG_MAJOR_VERSION"; exit $?'

sleep 3
echo "Completing pg_upgrade"
docker exec -it pg_upgrade_test bash -c '/tmp/upgrade/pg_upgrade_scripts/complete.sh; exit $?'

pg_prove tests/01-schema.sql
pg_prove tests/02-data.sql
pg_prove tests/03-settings.sql

