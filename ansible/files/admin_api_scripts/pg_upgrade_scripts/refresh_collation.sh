#! /usr/bin/env bash

## Rebuilds affected indexes and refreshes recorded collation versions after an
## AMI ships new glibc/ICU over existing data. Invoked on demand by adminapi (not
## a boot service); the exit code is the signal: 0 = work done, or a legitimate
## no-op (replica, pre-PG15); 1 = something failed, OR preconditions could not be
## established (Postgres unreachable) so we don't actually know the collation
## state. Per-statement errors don't abort — we fix what we can,
## then exit non-zero (like the sibling pg_upgrade scripts). Reindex runs BEFORE
## refresh so a stale index is never masked by an updated catalog; a failed reindex
## skips that database's refresh to preserve the signal.
##
## SECURITY: object names never reach the shell. Enumeration returns integer OIDs
## only; DDL is built and run server-side via format('%I',...) + \gexec, so a
## hostile collation/index name (any user with CREATE on a schema) can't inject a
## psql meta-command (\!) to get a root shell via this script's sudoers grant.

set -uo pipefail # deliberately NOT -e: per-statement errors are handled inline

# pg_database_collation_actual_version() + datcollversion are PG15+; nothing to
# compare against below that. (The collation-level function is older, but this
# database-level gate sets the floor.)
MIN_SERVER_VERSION_NUM=150000

# libc always; ICU always. Reindex-before-refresh makes ICU safe.
PROVIDERS="'c', 'i'"

# Caps REINDEX CONCURRENTLY's brief locks so one idle-in-transaction client can't
# block it forever. Passed via PGOPTIONS, not a ;-joined SET — that would open a
# transaction block, which REINDEX CONCURRENTLY refuses to run inside.
REINDEX_LOCK_TIMEOUT_MS=2000

# Set by any enumeration/reindex/refresh failure; becomes the exit code.
SCRIPT_FAILED=0

log() {
	echo "[$(date '+%Y-%m-%d %H:%M:%S')] refresh_collation: $1"
}

# ON_ERROR_STOP makes psql exit non-zero on any SQL error (incl. inside \gexec) —
# that is how per-statement failure is detected below.
run_sql() {
	psql -h localhost -U supabase_admin -v ON_ERROR_STOP=1 --no-psqlrc "$@"
}

# Retry to guard against a not-yet-ready Postgres socket.
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

# Wrap a db name in dbname='...' (escaping \ and ') so characters special to -d
# parsing (=, spaces, quotes) stay part of a literal name, not a conninfo fragment.
conninfo_for_db() {
	local d="$1"
	d="${d//\\/\\\\}"
	d="${d//\'/\\\'}"
	printf "dbname='%s'" "$d"
}

# --- Enumeration queries: emit integer OIDs only (never object names) ----------

# Leaf indexes ('i') in user schemas depending on a stale collation (explicit or
# the db default). Partitioned parents ('I') have no storage; catalogs use
# version-less collations; temp schemas are skipped (reindexing another session's
# temp index fails).
#
# SCOPE / KNOWN LIMITATION (follow-up): detection keys off pg_index.indcollation —
# the collations of the index's KEY COLUMNS only. Collation dependencies that live
# elsewhere are NOT detected and NOT rebuilt: partial-index predicates
# (pg_index.indpred), CHECK constraints (pg_constraint), and partition bound
# expressions (pg_class.relpartbound). The refresh step below bumps the recorded
# version for EVERY stale collation regardless of where it is used, so those
# dependencies get stamped "refreshed" without any revalidation. The intended
# follow-up surfaces them via the adminapi advisory channel rather than silently
# refreshing. See:
# https://github.com/supabase/postgres/pull/2343#discussion_r3756738261
affected_index_oids_sql() {
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
select i.indexrelid
from pg_index i
join pg_class ci on ci.oid = i.indexrelid
join pg_namespace n on n.oid = ci.relnamespace
where ci.relkind = 'i'
  and n.nspname not in ('pg_catalog', 'pg_toast', 'information_schema')
  and n.nspname not like 'pg\_temp\_%'
  and n.nspname not like 'pg\_toast\_temp\_%'
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
order by i.indexrelid;
SQL
}

# Named collations in the CURRENT database whose recorded version is stale.
stale_collation_oids_sql() {
	cat <<SQL
select c.oid
from pg_collation c
where c.collprovider in ($PROVIDERS)
  and c.collversion is not null
  and c.collversion is distinct from pg_collation_actual_version(c.oid)
order by c.oid;
SQL
}

# Databases with a stale default version. datallowconn is NOT filtered: template0
# rejects connections but ALTER DATABASE ... REFRESH runs from the shared catalog,
# so it must be refreshed too.
stale_db_default_oids_sql() {
	cat <<SQL
select oid
from pg_database
where datlocprovider in ($PROVIDERS)
  and datcollversion is not null
  and datcollversion is distinct from pg_database_collation_actual_version(oid)
order by oid;
SQL
}

# --- Server-side executors: DDL generated from an OID, run via \gexec ----------

reindex_index_by_oid() {
	local conn="$1" oid="$2"
	PGOPTIONS="-c lock_timeout=$REINDEX_LOCK_TIMEOUT_MS" run_sql -d "$conn" <<SQL
select format('reindex index concurrently %I.%I;', n.nspname, c.relname)
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where c.oid = $oid and c.relkind = 'i'
\gexec
SQL
}

refresh_collation_by_oid() {
	local conn="$1" oid="$2"
	run_sql -d "$conn" <<SQL
select format('alter collation %I.%I refresh version;', n.nspname, c.collname)
from pg_collation c
join pg_namespace n on n.oid = c.collnamespace
where c.oid = $oid
\gexec
SQL
}

refresh_db_default_by_oid() {
	local oid="$1"
	run_sql -d postgres <<SQL
select format('alter database %I refresh collation version;', datname)
from pg_database
where oid = $oid
\gexec
SQL
}

process_database() {
	local db="$1"
	local conn oids rc oid reindex_failed=0

	conn="$(conninfo_for_db "$db")"

	# a. Reindex first, so a stale index is never masked by an updated catalog.
	oids="$(run_sql -d "$conn" -Atq -c "$(affected_index_oids_sql)")"
	rc=$?
	if [ "$rc" -ne 0 ]; then
		log "WARN could not enumerate affected indexes on $db (psql rc=$rc); skipping refresh to preserve signal"
		SCRIPT_FAILED=1
		return
	fi
	while IFS= read -r oid; do
		[ -z "$oid" ] && continue
		if ! [[ $oid =~ ^[0-9]+$ ]]; then
			log "WARN ignoring non-numeric index oid '$oid' on $db"
			SCRIPT_FAILED=1
			reindex_failed=1
			continue
		fi
		log "reindex $db :: index oid $oid"
		if ! reindex_index_by_oid "$conn" "$oid"; then
			log "WARN reindex failed on $db :: index oid $oid (continuing)"
			SCRIPT_FAILED=1
			reindex_failed=1
		fi
	done <<<"$oids"

	# b. Refresh collation versions — only if every reindex succeeded, else we'd
	#    erase the signal that the index still needs rebuilding.
	if [ "$reindex_failed" -ne 0 ]; then
		log "skipping collation refresh on $db: reindex incomplete (stale-index signal preserved)"
		return
	fi

	oids="$(run_sql -d "$conn" -Atq -c "$(stale_collation_oids_sql)")"
	rc=$?
	if [ "$rc" -ne 0 ]; then
		log "WARN could not enumerate stale collations on $db (psql rc=$rc)"
		SCRIPT_FAILED=1
		return
	fi
	while IFS= read -r oid; do
		[ -z "$oid" ] && continue
		if ! [[ $oid =~ ^[0-9]+$ ]]; then
			log "WARN ignoring non-numeric collation oid '$oid' on $db"
			SCRIPT_FAILED=1
			continue
		fi
		log "refresh collation $db :: collation oid $oid"
		if ! refresh_collation_by_oid "$conn" "$oid"; then
			log "WARN collation refresh failed on $db :: collation oid $oid (continuing)"
			SCRIPT_FAILED=1
		fi
	done <<<"$oids"
}

main() {
	if ! retry 8 pg_isready -h localhost -U supabase_admin -d postgres; then
		log "postgres not ready after retries; could not run (reporting failure)"
		SCRIPT_FAILED=1
		return
	fi

	# Read replica: catalogs are read-only (changes stream from the primary) and
	# every REINDEX/ALTER would fail "read-only transaction"; skip.
	local in_recovery
	in_recovery="$(run_sql -d postgres -Atq -c "select pg_is_in_recovery();")" || in_recovery=""
	if [ "$in_recovery" = "t" ]; then
		log "server is in recovery (replica); skipping"
		return 0
	fi

	# Unknown/non-numeric version must not pass the floor check — skip, don't proceed.
	local svn
	svn="$(run_sql -d postgres -Atq -c "select current_setting('server_version_num');")" || svn=""
	if ! [[ $svn =~ ^[0-9]+$ ]]; then
		log "could not read a numeric server_version_num (got '${svn}'); skipping"
		return 0
	fi
	if [ "$svn" -lt "$MIN_SERVER_VERSION_NUM" ]; then
		log "server_version_num=$svn < $MIN_SERVER_VERSION_NUM; collation version tracking unavailable, skipping"
		return 0
	fi

	local dbs rc db oids oid
	dbs="$(run_sql -d postgres -Atq -c "select datname from pg_database where datallowconn and datname <> 'template0' order by datname;")"
	rc=$?
	if [ "$rc" -ne 0 ]; then
		log "WARN could not enumerate databases (psql rc=$rc)"
		SCRIPT_FAILED=1
		return
	fi
	while IFS= read -r db; do
		[ -z "$db" ] && continue
		process_database "$db"
	done <<<"$dbs"

	# c. Database-default versions (shared catalog), after every db's default-
	#    collated indexes were reindexed above. Includes template0.
	oids="$(run_sql -d postgres -Atq -c "$(stale_db_default_oids_sql)")"
	rc=$?
	if [ "$rc" -ne 0 ]; then
		log "WARN could not enumerate stale database defaults (psql rc=$rc)"
		SCRIPT_FAILED=1
	else
		while IFS= read -r oid; do
			[ -z "$oid" ] && continue
			if ! [[ $oid =~ ^[0-9]+$ ]]; then
				log "WARN ignoring non-numeric database oid '$oid'"
				SCRIPT_FAILED=1
				continue
			fi
			log "refresh (db default) :: database oid $oid"
			if ! refresh_db_default_by_oid "$oid"; then
				log "WARN database-default refresh failed :: database oid $oid (continuing)"
				SCRIPT_FAILED=1
			fi
		done <<<"$oids"
	fi

	log "done (failed=$SCRIPT_FAILED)"
}

main
exit "$SCRIPT_FAILED"
