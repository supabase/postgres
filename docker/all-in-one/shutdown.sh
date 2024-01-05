#!/bin/bash

# This script provides a method of shutting down the machine/container when the database has been idle
#  for a certain amount of time (configurable via the MAX_IDLE_TIME_MINUTES env var)
#
# It checks for any active (non-idle) connections and for any connections which have been idle for more than MAX_IDLE_TIME_MINUTES.
# If there are no active connections and no idle connections, it then checks if the last disconnection event happened more than MAX_IDLE_TIME_MINUTES ago.
# 
# If all of these conditions are met, then Postgres is shut down, allowing it to wrap up any pending transactions (such as WAL shippipng) and gracefully exit.
# To terminate the machine/container, a SIGTERM signal is sent to the top-level process (supervisord) which will then shut down all other processes and exit.

DEFAULT_MAX_IDLE_TIME_MINUTES=${MAX_IDLE_TIME_MINUTES:-5}
CONFIG_FILE_PATH=${CONFIG_FILE_PATH:-/etc/supa-shutdown/shutdown.conf}

run_sql() {
  psql -h localhost -U supabase_admin -d postgres "$@"
}

check_activity() {
  pg_isready -h localhost > /dev/null 2>&1 || (echo "Postgres is not ready yet" && exit 1)

  QUERY=$(cat <<SQL
WITH
non_idling_connections AS (SELECT * FROM pg_stat_activity WHERE state IS NOT NULL AND state != 'idle'),
recent_idling_connections AS (SELECT * FROM pg_stat_activity WHERE state = 'idle' AND (now() - query_start) < interval '$MAX_IDLE_TIME_MINUTES minutes')
SELECT count(*) FROM (
  SELECT * FROM non_idling_connections
  UNION
  SELECT * FROM recent_idling_connections
) t
WHERE pid != pg_backend_pid() 
  AND backend_type = 'client backend' 
  AND client_addr IS NOT NULL 
  AND query != 'LISTEN "pgrst"'
  AND (
    usename IN ('supabase_auth_admin', 'authenticator')
    OR client_addr NOT IN (inet '127.0.0.1', inet '::1')
  );
SQL
)

  ACTIVE_CONN_COUNT=$(run_sql -tA -c "$QUERY")

  # If there are any active connections, return early since we don't want to shut down
  if [ "$ACTIVE_CONN_COUNT" -gt 0 ]; then
    return 0
  fi

  LAST_DISCONNECT_TIME=$(date -d "$(cat "/var/log/postgresql/postgresql.csv" | grep "disconnection: session time" | grep -vw "host=127.0.0.1\|host=::1\|host=\[local\]" | tail -n 1 | cut -c1-19)" +%s 2>/dev/null || echo 0)
  NOW=$(date +%s)
  TIME_SINCE_LAST_DISCONNECT="$((NOW - LAST_DISCONNECT_TIME))"

  if [ $TIME_SINCE_LAST_DISCONNECT -gt "$((MAX_IDLE_TIME_MINUTES * 60))" ]; then
    echo "$(date): No active connections for $MAX_IDLE_TIME_MINUTES minutes. Shutting down."

    supervisorctl stop postgresql

    # Postgres ships the latest WAL file using archive_command during shutdown, in a blocking operation
    # This is to ensure that the WAL file is shipped, just in case
    sleep 1

    /usr/bin/admin-mgr lsn-checkpoint-push --immediately || echo "Failed to push LSN checkpoint"

    kill -s TERM "$(supervisorctl pid)"
  fi
}

# Enable logging of disconnections so the script can check when the last disconnection happened
run_sql -c "ALTER SYSTEM SET log_disconnections = 'on';"
run_sql -c "SELECT pg_reload_conf();"

sleep $((DEFAULT_MAX_IDLE_TIME_MINUTES * 60))
while true; do
  if [ -f "$CONFIG_FILE_PATH" ]; then
    source "$CONFIG_FILE_PATH"

    if [ -z "$SHUTDOWN_IDLE_TIME_MINUTES" ]; then
      MAX_IDLE_TIME_MINUTES="$DEFAULT_MAX_IDLE_TIME_MINUTES"
    else
      MAX_IDLE_TIME_MINUTES="$SHUTDOWN_IDLE_TIME_MINUTES"
    fi
  else
    MAX_IDLE_TIME_MINUTES="$DEFAULT_MAX_IDLE_TIME_MINUTES"
  fi

  check_activity
  sleep 30
done
