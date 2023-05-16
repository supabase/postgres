#! /usr/bin/env bash

# Common functions and variables used by pg_upgrade_initiate.sh and pg_upgrade_complete.sh

REPORTING_PROJECT_REF="ihmaxnjpcccasmrbkpvo"
REPORTING_CREDENTIALS_FILE="/root/upgrade-reporting-credentials"

REPORTING_ANON_KEY=""
if [ -f "$REPORTING_CREDENTIALS_FILE" ]; then
    REPORTING_ANON_KEY=$(cat "$REPORTING_CREDENTIALS_FILE")
fi

function run_sql {
    psql -h localhost -U supabase_admin -d postgres "$@"
}

function ship_logs {
    LOG_FILE=$1

    if [ -z "$REPORTING_ANON_KEY" ]; then
        echo "No reporting key found. Skipping log upload."
        return 0
    fi

    if [ ! -f "$LOG_FILE" ]; then
        echo "No log file found. Skipping log upload."
        return 0
    fi

    if [ ! -s "$LOG_FILE" ]; then
        echo "Log file is empty. Skipping log upload."
        return 0
    fi

    HOSTNAME=$(hostname)
    DERIVED_REF="${HOSTNAME##*-}"

    printf -v BODY '{ "ref": "%s", "step": "%s", "content": %s }' "$DERIVED_REF" "completion" "$(cat "$LOG_FILE" | jq -Rs '.')"
    curl -sf -X POST "https://$REPORTING_PROJECT_REF.supabase.co/rest/v1/error_logs" \
         -H "apikey: ${REPORTING_ANON_KEY}" \
         -H 'Content-type: application/json' \
         -d "$BODY"
}

function retry {
  local retries=$1
  shift

  local count=0
  until "$@"; do
    exit=$?
    wait=$((2 ** (count + 1)))
    count=$((count + 1))
    if [ $count -lt "$retries" ]; then
        echo "Command $* exited with code $exit, retrying..."
        sleep $wait
    else
        echo "Command $* exited with code $exit, no more retries left."
        return $exit
    fi
  done
  return 0
}
