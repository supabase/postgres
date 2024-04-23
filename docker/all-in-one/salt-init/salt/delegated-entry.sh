#!/usr/bin/env bash

# script can take 1 argument the start time
if [ -z $1 ]; then
  START_TIME=$(date +%s%N)
else
  START_TIME=$1
fi

## FUNCTONS ##########

function calculate_duration {
  local start_time=$1
  local end_time=$2

  local duration=$((end_time - start_time))
  local milliseconds=$((duration / 1000000))

  echo "$milliseconds"
}

function report_health {
  if [ -z "${REPORTING_TOKEN:-}" ]; then
    echo "Skipped health reporting: missing REPORTING_TOKEN"
    exit 0
  fi
  if [ -d "$ADMIN_API_CERT_DIR" ]; then
    retry 10 curl -sSkf "https://localhost:$ADMIN_API_PORT/health-reporter/send" -X POST -H "apikey: $ADMIN_API_KEY"
  else
    retry 10 curl -sSf "http://localhost:$ADMIN_API_PORT/health-reporter/send" -X POST -H "apikey: $ADMIN_API_KEY"
  fi
}

function start_supervisor {
  # Start health reporting
  report_health &

  # Start supervisord
  /usr/bin/supervisord -c $SUPERVISOR_CONF
}


## START ##########
echo "Delegated Entry Script"
SUPERVISOR_CONF=/etc/supervisor/supervisord.conf

# configure things with salt
echo "Applying salt state"
/usr/bin/salt-call state.apply # -l debug
DURATION=$(calculate_duration "$START_TIME" "$(date +%s%N)")
echo "DE: Execution time to finishing salt apply: $DURATION milliseconds"

## Add extra or custom logic here ##

####################################

# Finally
DURATION=$(calculate_duration "$START_TIME" "$(date +%s%N)")
echo "DE: Execution time to starting supervisor: $DURATION milliseconds"
start_supervisor
