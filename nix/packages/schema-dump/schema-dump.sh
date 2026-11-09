#!/usr/bin/env bash

set -euo pipefail

# These all come from the derivation, make shellcheck happy
: "${out?}" "${PGDATABASE?}" "${PGHOST?}" "${PGPORT?}" "${PGUSER?}"

d=$(mktemp -d)
datdir=$d/pg

if (($# != 4)); then
	echo "unexpected number of cli args: want 4, got $#" >&2
	exit 1
fi

version=$1
migrations_dir=$2
pgbouncer_auth_schema_sql=$3
stat_extension_sql=$4

psql() { command psql -v ON_ERROR_STOP=1 --no-password --no-psqlrc "$@"; }
cleanup() { pg_ctl -D "$datdir" stop -m fast &>/dev/null || true; }
trap cleanup EXIT

start-postgres-server "$version" --skip-migrations --daemonize --datdir "$datdir"

for _ in $(seq 60); do
	pg_isready -q && break
	sleep 1
done
pg_isready

if [[ $version == orioledb-17 ]]; then
	psql -tAc "select amname from pg_am where amname = 'orioledb'" | grep -q orioledb
fi

psql -c "create role postgres superuser login; alter database $PGDATABASE owner to postgres"

PGUSER=postgres psql -f "$pgbouncer_auth_schema_sql"
PGUSER=postgres psql -f "$stat_extension_sql"

DATABASE_URL="postgres://postgres@$PGHOST:$PGPORT/$PGDATABASE?sslmode=disable" \
	dbmate --no-dump-schema --migrations-dir "$migrations_dir/init-scripts" up

DATABASE_URL="postgres://$PGUSER@$PGHOST:$PGPORT/$PGDATABASE?sslmode=disable" \
	dbmate --no-dump-schema --migrations-dir "$migrations_dir/migrations" up

mkdir "$out"
pg_dump --schema-only --no-owner --no-privileges --restrict-key=SupabaseTestDumpKey123 >"$out/schema.sql"

# the migrations must be safe to run again
for sql in "$migrations_dir"/migrations/*.sql; do
	echo "re-running $sql"
	psql -f "$sql"
done
