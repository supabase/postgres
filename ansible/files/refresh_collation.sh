#! /usr/bin/env bash

## Boot-time collation gate: runs once after postgresql.service and BEFORE the
## traffic-facing services (ordered via systemd). When a new AMI ships an upgraded
## glibc and/or ICU over an existing data volume, it reindexes every affected
## index and then refreshes the recorded collation versions, so no warnings or
## deferred reindexing remain once traffic is admitted. Plain (non-concurrent)
## REINDEX is used since no clients are connected yet; reindex-before-refresh also
## makes the bare REFRESH safe for both providers (libc 'c' and ICU 'i').
##
## FAIL-OPEN: per-statement errors are logged and skipped and the script exits 0,
## so the gate never wedges boot. The platform refreshCollationVersion task
## (REINDEX CONCURRENTLY under traffic) is the backstop for oversized indexes.

set -uo pipefail # deliberately NOT -e: we handle errors per statement (fail-open)

# pg_database_collation_actual_version / pg_collation_actual_version were added in
# PG15 — below that there is nothing to compare against.
MIN_SERVER_VERSION_NUM=150000

log() {
	echo "[$(date '+%Y-%m-%d %H:%M:%S')] refresh_collation: $1"
}

# Match the connection style used by the pg_upgrade scripts' run_sql.
run_sql() {
	psql -h localhost -U supabase_admin -v ON_ERROR_STOP=1 --no-psqlrc "$@"
}

# Retry a command a few times (Postgres should already be up via
# After=postgresql.service, but guard against a slow socket at boot).
retry() {
	local attempts=$1
	shift
	local i=0
	until "$@"; do
		i=$((i + 1))
		if [ "$i" -ge "$attempts" ]; then
			return 1
		fi
		sleep 1
	done
	return 0
}

# libc always; ICU always. Reindex-before-refresh makes ICU safe.
PROVIDERS="'c', 'i'"

# Indexes in the CURRENT database whose columns depend on a version-mismatched
# collation (explicit or the database default). Leaf indexes ('i') in user
# schemas only: partitioned parents ('I') have no storage, and system catalogs
# index version-less collations so they are immune. Emits %I.%I-quoted names.
affected_indexes_sql() {
	cat <<SQL
with affected_coll as (
  select c.oid
  from pg_collation c
  where c.collprovider in ($PROVIDERS)
    and c.collversion is not null
    and c.collversion is distinct from pg_collation_actual_version(c.oid)
),
affected_default as (
  select 1
  from pg_database d
  where d.datname = current_database()
    and d.datlocprovider in ($PROVIDERS)
    and d.datcollversion is not null
    and d.datcollversion is distinct from pg_database_collation_actual_version(d.oid)
)
select distinct format('%I.%I', n.nspname, ci.relname) as index_name
from pg_index i
join pg_class ci on ci.oid = i.indexrelid
join pg_namespace n on n.oid = ci.relnamespace
where ci.relkind = 'i'
  and n.nspname not in ('pg_catalog', 'pg_toast', 'information_schema')
  and (
    exists (
      select 1 from unnest(i.indcollation) as ic(oid)
      where ic.oid in (select oid from affected_coll)
    )
    or (
      exists (select 1 from affected_default)
      and exists (
        select 1 from unnest(i.indcollation) as ic(oid)
        where ic.oid = 'pg_catalog."default"'::regcollation
      )
    )
  )
order by index_name;
SQL
}

# Named collations in the CURRENT database whose recorded version is stale.
collation_refresh_sql() {
	cat <<SQL
select format('alter collation %I.%I refresh version;', n.nspname, c.collname) as stmt
from pg_collation c
join pg_namespace n on n.oid = c.collnamespace
where c.collprovider in ($PROVIDERS)
  and c.collversion is not null
  and c.collversion is distinct from pg_collation_actual_version(c.oid)
order by n.nspname, c.collname;
SQL
}

# Database-default versions from the shared pg_database catalog — evaluable from a
# single connection and applicable to every database.
database_default_refresh_sql() {
	cat <<SQL
select format('alter database %I refresh collation version;', datname) as stmt
from pg_database
where datallowconn
  and datlocprovider in ($PROVIDERS)
  and datcollversion is not null
  and datcollversion is distinct from pg_database_collation_actual_version(oid)
order by datname;
SQL
}

process_database() {
	local db="$1"
	local index stmt

	# a. Reindex affected indexes BEFORE refreshing (PostgreSQL ALTER COLLATION
	#    docs) so a stale index is never left masked by an updated catalog.
	while IFS= read -r index; do
		[ -z "$index" ] && continue
		log "reindex $db :: $index"
		if ! run_sql -d "$db" -c "reindex index $index;"; then
			log "WARN reindex failed on $db :: $index (continuing, fail-open)"
		fi
	done < <(run_sql -d "$db" -Atq -c "$(affected_indexes_sql)")

	# b. Refresh named collation versions in this database, after the reindex.
	while IFS= read -r stmt; do
		[ -z "$stmt" ] && continue
		log "refresh $db :: $stmt"
		if ! run_sql -d "$db" -c "$stmt"; then
			log "WARN collation refresh failed on $db :: $stmt (continuing, fail-open)"
		fi
	done < <(run_sql -d "$db" -Atq -c "$(collation_refresh_sql)")
}

main() {
	if ! retry 8 pg_isready -h localhost -U supabase_admin -d postgres; then
		log "postgres not ready after retries; skipping (fail-open)"
		return 0
	fi

	local svn
	svn=$(run_sql -d postgres -Atq -c "select current_setting('server_version_num');") || svn=0
	if [ "${svn:-0}" -lt "$MIN_SERVER_VERSION_NUM" ]; then
		log "server_version_num=${svn:-unknown} < $MIN_SERVER_VERSION_NUM; *_collation_actual_version() unavailable, skipping"
		return 0
	fi

	local db stmt
	while IFS= read -r db; do
		[ -z "$db" ] && continue
		process_database "$db"
	done < <(run_sql -d postgres -Atq -c "select datname from pg_database where datallowconn and datname <> 'template0' order by datname;")

	# c. Database-default versions (shared catalog) — after every database's
	#    default-collated indexes have been reindexed above.
	while IFS= read -r stmt; do
		[ -z "$stmt" ] && continue
		log "refresh (db default) :: $stmt"
		if ! run_sql -d postgres -c "$stmt"; then
			log "WARN database-default refresh failed :: $stmt (continuing, fail-open)"
		fi
	done < <(run_sql -d postgres -Atq -c "$(database_default_refresh_sql)")

	log "done"
}

main
exit 0
