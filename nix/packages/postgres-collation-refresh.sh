# shellcheck shell=bash
export PGHOST="${PGHOST:-localhost}"
export PGUSER="${PGUSER:-supabase_admin}"

run_sql() {
	psql -X -q -A -t -v ON_ERROR_STOP=1 -d postgres "$@"
}

# English ordering is identical across MIN_GLIBC..MAX_GLIBC, so a stale glibc
# en_US database is only refreshed when both versions sit in that range.
checked_cte() {
	cat <<SQL
with stale as (
  select datname,
         string_to_array(datcollversion, '.')::int[] as recorded,
         string_to_array(pg_database_collation_actual_version(oid), '.')::int[] as actual
  from pg_database
  where datlocprovider = 'c'
    and datcollate in ('en_US.UTF-8', 'en_US.utf8')
    and datcollversion is not null
    and datcollversion <> pg_database_collation_actual_version(oid)
),
checked as (
  select datname,
         recorded between string_to_array('$MIN_GLIBC', '.')::int[] and string_to_array('$MAX_GLIBC', '.')::int[]
         and actual between string_to_array('$MIN_GLIBC', '.')::int[] and string_to_array('$MAX_GLIBC', '.')::int[] as in_bounds
  from stale
)
SQL
}

if [ "$(run_sql -c "select pg_is_in_recovery()")" = "t" ]; then
	echo "collation_refresh: replica, skipping"
	exit 0
fi

# No ON_ERROR_STOP: one failing database must not stop the others. Failures
# surface in the remaining count below.
psql -X -q -A -t -d postgres <<SQL
$(checked_cte)
select format('alter database %I refresh collation version', datname)
from checked
where in_bounds
order by datname
\gexec
SQL

remaining="$(run_sql -c "$(checked_cte) select count(*) from checked")"
if [ "$remaining" -gt 0 ]; then
	echo "collation_refresh: $remaining database(s) still stale, refused or failed (glibc window $MIN_GLIBC..$MAX_GLIBC)"
	exit 1
fi
