#!/bin/sh

MAX_IDLE_TIME_MINUTES=${MAX_IDLE_TIME_MINUTES:-5}

run_sql() {
  psql -h localhost -U supabase_admin -d postgres "$@"
}

check_activity() {
  pg_isready -h localhost > /dev/null 2>&1 || (echo "Postgres is not ready yet" && exit 1)

  QUERY=$(cat <<SQL
WITH
non_idling_connections AS (SELECT * FROM pg_stat_activity WHERE state IS NOT NULL null AND state != 'idle'),
recent_idling_connections AS (SELECT * FROM pg_stat_activity WHERE state = 'idle' AND (now() - query_start) < interval '$MAX_IDLE_TIME_MINUTES minutes')
SELECT count(*) FROM (
  SELECT * FROM non_idling_connections
  UNION
  SELECT * FROM recent_idling_connections
) t
WHERE pid != pg_backend_pid() 
  AND backend_type = 'client backend' 
  AND client_addr is not null 
  AND query != 'LISTEN "pgrst"'
  AND (
    usename IN ('supabase_auth_admin', 'authenticator')
    OR client_addr NOT IN (inet '127.0.0.1', inet '::1')
  );
SQL
)

  ACTIVE_CONN_COUNT=$(echo "$QUERY" | psql -U postgres -tA)

  LAST_DISCONNECT_TIME=$(date -d "$(cat "/var/log/postgresql/postgresql.csv" | grep "disconnection: session time" | grep -vw "host=127.0.0.1\|host=::1\|host=\[local\]" | tail -n 1 | cut -c1-19)" +%s 2>/dev/null || echo 0)
  NOW=$(date +%s)
  TIME_SINCE_LAST_DISCONNECT="$((NOW - LAST_DISCONNECT_TIME))"

  if [ "$ACTIVE_CONN_COUNT" = "0" ] && [ $TIME_SINCE_LAST_DISCONNECT -gt "$((MAX_IDLE_TIME_MINUTES * 60))" ]; then
    LAST_WAL_FILE_NAME=$(run_sql -tA -c "SELECT pg_walfile_name(pg_switch_wal())")
    NEW_WAL_FILE_NAME=$(run_sql -tA -c "SELECT pg_walfile_name(pg_current_wal_lsn())")

    echo "$(date): No active connections for $MAX_IDLE_TIME_MINUTES minutes. Shutting down."

    supervisorctl stop postgresql

    # Postgres ships the latest WAL file using archive_commAND during shutdown, in a blocking operation
    # This is to ensure that the WAL file is shipped, just in case
    if [ "$LAST_WAL_FILE_NAME" != "$NEW_WAL_FILE_NAME" ]; then
        sleep 2
    fi

    kill -s TERM "$(supervisorctl pid)"
  fi
}

sleep $((MAX_IDLE_TIME_MINUTES * 60))
while true; do
  check_activity
  sleep 30
done
