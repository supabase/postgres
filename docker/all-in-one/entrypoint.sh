#!/bin/bash
set -eou pipefail

START_TIME=$(date +%s%N)

PG_CONF=/etc/postgresql/postgresql.conf
SUPERVISOR_CONF=/etc/supervisor/supervisord.conf

export DATA_VOLUME_MOUNTPOINT=${DATA_VOLUME_MOUNTPOINT:-/data}
export CONFIGURED_FLAG_PATH=${CONFIGURED_FLAG_PATH:-$DATA_VOLUME_MOUNTPOINT/machine.configured}

export MAX_IDLE_TIME_MINUTES=${MAX_IDLE_TIME_MINUTES:-5}

function calculate_duration {
  local start_time=$1
  local end_time=$2

  local duration=$((end_time - start_time))
  local milliseconds=$((duration / 1000000))

  echo "$milliseconds"
}

# Ref: https://gist.github.com/sj26/88e1c6584397bb7c13bd11108a579746
function retry {
  # Pass 0 for unlimited retries
  local retries=$1
  shift

  local start=$EPOCHSECONDS
  local count=0
  until "$@"; do
    exit=$?
    # Reset count if service has been running for more than 2 minutes
    local elapsed=$((EPOCHSECONDS - start))
    if [ $elapsed -gt 120 ]; then
      count=0
    fi
    # Exponential backoff up to n tries
    local wait=$((2 ** count))
    count=$((count + 1))
    if [ $count -ge "$retries" ] && [ "$retries" -gt 0 ]; then
      echo "Retry $count/$retries exited $exit, no more retries left."
      return $exit
    fi
    echo "Retry $count/$retries exited $exit, retrying in $wait seconds..."
    sleep $wait
    start=$EPOCHSECONDS
  done
  return 0
}

function configure_services {
  # Start services after migrations are run
  for file in /init/configure-*.sh; do
    retry 0 "$file"
  done
}

function enable_swap {
  fallocate -l 1G /mnt/swapfile
  chmod 600 /mnt/swapfile
  mkswap /mnt/swapfile
  swapon /mnt/swapfile
}

function push_lsn_checkpoint_file {
  if [ "${PLATFORM_DEPLOYMENT:-}" != "true" ]; then
    echo "Skipping push of LSN checkpoint file"
    return
  fi

  /usr/bin/admin-mgr lsn-checkpoint-push --immediately || echo "Failed to push LSN checkpoint"
}

function graceful_shutdown {
  echo "$(date): Received SIGINT. Shutting down."

  # Postgres ships the latest WAL file using archive_command during shutdown, in a blocking operation
  # This is to ensure that the WAL file is shipped, just in case
  sleep 0.2
  push_lsn_checkpoint_file
}

function enable_autoshutdown {
  sed -i "s/autostart=.*/autostart=true/" /etc/supervisor/base-services/supa-shutdown.conf
}

function enable_lsn_checkpoint_push {
  sed -i "s/autostart=.*/autostart=true/" /etc/supervisor/base-services/lsn-checkpoint-push.conf
  sed -i "s/autorestart=.*/autorestart=true/" /etc/supervisor/base-services/lsn-checkpoint-push.conf
}

function disable_fail2ban {
  sed -i "s/autostart=.*/autostart=false/" /etc/supervisor/services/fail2ban.conf
  sed -i "s/autorestart=.*/autorestart=false/" /etc/supervisor/services/fail2ban.conf
}

function setup_postgres {
  tar -xzvf "$INIT_PAYLOAD_PATH" -C / ./etc/postgresql.schema.sql
  mv /etc/postgresql.schema.sql /docker-entrypoint-initdb.d/migrations/99-schema.sql

  tar -xzvf "$INIT_PAYLOAD_PATH" -C / ./etc/postgresql-custom/pgsodium_root.key
  sed -i "/# Automatically generated optimizations/i # Supabase Platform Defaults\ninclude = '/etc/postgresql-custom/platform-defaults.conf'\n" $PG_CONF

  # TODO (darora): walg enablement is temporarily performed here until changes from https://github.com/supabase/postgres/pull/639 get picked up
  # other things will still be needed in the future (auth_delay config)
  sed -i \
    -e "s|#include = '/etc/postgresql-custom/custom-overrides.conf'|include = '/etc/postgresql-custom/custom-overrides.conf'|g" \
    -e "s|#include = '/etc/postgresql-custom/wal-g.conf'|include = '/etc/postgresql-custom/wal-g.conf'|g" \
    -e "s|shared_preload_libraries = '\(.*\)'|shared_preload_libraries = '\1, auth_delay'|" \
    -e "/# Automatically generated optimizations/i auth_delay.milliseconds = '3000'" \
    "${PG_CONF}"

  # Setup ssl certs
  mkdir -p /etc/ssl/certs/postgres
  tar -xzvf "$INIT_PAYLOAD_PATH" -C /etc/ssl/certs/postgres/ --strip-components 2 ./ssl/server.crt
  tar -xzvf "$INIT_PAYLOAD_PATH" -C /etc/ssl/certs/postgres/ --strip-components 2 ./ssl/ca.crt
  tar -xzvf "$INIT_PAYLOAD_PATH" -C /etc/ssl/private/ --strip-components 2 ./ssl/server.key
  # tar -xzvf "$INIT_PAYLOAD_PATH" -C /etc/ssl/certs/postgres/ ./ssl/server-intermediate.srl

  PGSSLROOTCERT=/etc/ssl/certs/postgres/ca.crt
  PGSSLCERT=/etc/ssl/certs/postgres/server.crt
  PGSSLKEY=/etc/ssl/private/server.key
  chown root:postgres $PGSSLROOTCERT $PGSSLKEY $PGSSLCERT
  chmod 640 $PGSSLROOTCERT $PGSSLKEY $PGSSLCERT

  # Change ssl back to on in postgres.conf
  sed -i -e "s|ssl = off|ssl = on|g" \
    -e "s|ssl_ca_file = ''|ssl_ca_file = '$PGSSLROOTCERT'|g" \
    -e "s|ssl_cert_file = ''|ssl_cert_file = '$PGSSLCERT'|g" \
    -e "s|ssl_key_file = ''|ssl_key_file = '$PGSSLKEY'|g" \
    $PG_CONF

  if [ "${DATA_VOLUME_MOUNTPOINT}" ]; then
    mkdir -p "${DATA_VOLUME_MOUNTPOINT}/opt"
    /usr/local/bin/configure-shim.sh /dist/supabase-admin-api /opt/supabase-admin-api
    /opt/supabase-admin-api optimize db --destination-config-file-path /etc/postgresql-custom/generated-optimizations.conf

    # Preserve postgresql configs across restarts
    POSTGRESQL_CUSTOM_DIR="${DATA_VOLUME_MOUNTPOINT}/etc/postgresql-custom"

    mkdir -p "${POSTGRESQL_CUSTOM_DIR}"

    if [ ! -f "${CONFIGURED_FLAG_PATH}" ]; then
      echo "Copying existing custom postgresql config from /etc/postgresql-custom to ${POSTGRESQL_CUSTOM_DIR}"
      cp -R "/etc/postgresql-custom/." "${POSTGRESQL_CUSTOM_DIR}/"
    fi

    rm -rf "/etc/postgresql-custom"
    ln -s "${POSTGRESQL_CUSTOM_DIR}" "/etc/postgresql-custom"
    chown -R postgres:postgres "/etc/postgresql-custom"
    chown -R postgres:postgres "${POSTGRESQL_CUSTOM_DIR}"
    chmod g+rx "${POSTGRESQL_CUSTOM_DIR}"

    # Preserve wal-g configs across restarts
    WALG_CONF_DIR="${DATA_VOLUME_MOUNTPOINT}/etc/wal-g"
    mkdir -p "${WALG_CONF_DIR}"

    if [ ! -f "${CONFIGURED_FLAG_PATH}" ]; then
      echo "Copying existing custom wal-g config from /etc/wal-g to ${WALG_CONF_DIR}"
      cp -R "/etc/wal-g/." "${WALG_CONF_DIR}/"
    fi

    rm -rf "/etc/wal-g"
    ln -s "${WALG_CONF_DIR}" "/etc/wal-g"
    chown -R adminapi:adminapi "/etc/wal-g"
    chown -R adminapi:adminapi "${WALG_CONF_DIR}"
    chmod g+rx "/etc/wal-g"
    chmod g+rx "${WALG_CONF_DIR}"
  fi
  DURATION=$(calculate_duration "$START_TIME" "$(date +%s%N)")
  echo "E: Execution time to setting up postgresql: $DURATION milliseconds"
}

function setup_credentials {
  # Load credentials from init json
  tar -xzvf "$INIT_PAYLOAD_PATH" -C / ./tmp/init.json
  export ANON_KEY=${ANON_KEY:-$(jq -r '.["anon_key"]' /tmp/init.json)}
  export SERVICE_ROLE_KEY=${SERVICE_ROLE_KEY:-$(jq -r '.["service_key"]' /tmp/init.json)}
  export ADMIN_API_KEY=${ADMIN_API_KEY:-$(jq -r '.["supabase_admin_key"]' /tmp/init.json)}
  export JWT_SECRET=${JWT_SECRET:-$(jq -r '.["jwt_secret"]' /tmp/init.json)}
  DURATION=$(calculate_duration "$START_TIME" "$(date +%s%N)")
  echo "E: Execution time to setting up credentials: $DURATION milliseconds"
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

function run_prelaunch_hooks {
  if [ -f "/etc/postgresql-custom/supautils.conf" ]; then
    sed -i -e 's/dblink, //' "/etc/postgresql-custom/supautils.conf"
  fi
}

function start_supervisor {
  # Start health reporting
  report_health &

  # Start supervisord
  /usr/bin/supervisord -c $SUPERVISOR_CONF
}

DELEGATED_ARCHIVE_PATH=/data/delegated-init.tar.gz
DELEGATED_ENTRY_PATH=/data/delegated-entry.sh

function fetch_and_execute_delegated_payload {
  curl -s --time-cond $DELEGATED_ARCHIVE_PATH -o $DELEGATED_ARCHIVE_PATH "$DELEGATED_INIT_LOCATION"

  if [ ! -f $DELEGATED_ARCHIVE_PATH ]; then
    echo "No delegated payload found, bailing"
    return
  fi

  # only extract a valid archive
  if tar -tzf "$DELEGATED_ARCHIVE_PATH" &>/dev/null; then
    TAR_MTIME_EPOCH=$(tar -tvzf "$DELEGATED_ARCHIVE_PATH" delegated-entry.sh | awk '{print $4, $5}' | xargs -I {} date -d {} +%s)

    if [ -f $DELEGATED_ENTRY_PATH ]; then
      FILE_MTIME_EPOCH=$(stat -c %Y "$DELEGATED_ENTRY_PATH")

      if [ "$TAR_MTIME_EPOCH" -gt "$FILE_MTIME_EPOCH" ]; then
        tar -xvzf "$DELEGATED_ARCHIVE_PATH" -C /data
      else
        echo "TAR archive is not newer, skipping extraction"
      fi
    else
      tar -xvzf "$DELEGATED_ARCHIVE_PATH" -C /data
    fi
  else
    echo "Invalid TAR archive"
    return
  fi

  # Run our delegated entry script here
  if [ -f "$DELEGATED_ENTRY_PATH" ]; then
    chmod +x $DELEGATED_ENTRY_PATH
    bash -c "$DELEGATED_ENTRY_PATH $START_TIME"
  fi
}

# Increase max number of open connections
ulimit -n 65536

# Update pgsodium root key
if [ "${PGSODIUM_ROOT_KEY:-}" ]; then
  echo "${PGSODIUM_ROOT_KEY}" >/etc/postgresql-custom/pgsodium_root.key
fi

# Update pgdata directory
if [ "${PGDATA_REAL:-}" ]; then
  mkdir -p "${PGDATA_REAL}"
  chown -R postgres:postgres "${PGDATA_REAL}"
  chmod -R g+rx "${PGDATA_REAL}"
fi

if [ "${PGDATA:-}" ]; then
  if [ "${PGDATA_REAL:-}" ]; then
    mkdir -p "$(dirname "${PGDATA}")"
    rm -rf "${PGDATA}"
    ln -s "${PGDATA_REAL}" "${PGDATA}"
    chmod -R g+rx "${PGDATA}"
  else
    mkdir -p "$PGDATA"
    chown postgres:postgres "$PGDATA"
  fi
  sed -i "s|data_directory = '.*'|data_directory = '$PGDATA'|g" $PG_CONF
fi

# Download and extract init payload from s3
export INIT_PAYLOAD_PATH=${INIT_PAYLOAD_PATH:-/tmp/payload.tar.gz}

if [ "${INIT_PAYLOAD_PRESIGNED_URL:-}" ]; then
  curl -fsSL "$INIT_PAYLOAD_PRESIGNED_URL" -o "/tmp/payload.tar.gz" || true
  if [ -f "/tmp/payload.tar.gz" ] && [ "/tmp/payload.tar.gz" != "$INIT_PAYLOAD_PATH" ]; then
    mv "/tmp/payload.tar.gz" "$INIT_PAYLOAD_PATH"
  fi
fi

if [ "${DATA_VOLUME_MOUNTPOINT}" ]; then
  BASE_LOGS_FOLDER="${DATA_VOLUME_MOUNTPOINT}/logs"

  for folder in "postgresql" "services" "wal-g"; do
    mkdir -p "${BASE_LOGS_FOLDER}/${folder}"
    rm -rf "/var/log/${folder}"
    ln -s "${BASE_LOGS_FOLDER}/${folder}" "/var/log/${folder}"
  done

  chown -R postgres:postgres "${BASE_LOGS_FOLDER}"

  mkdir -p "${DATA_VOLUME_MOUNTPOINT}/etc/logrotate"
fi

# Process init payload
if [ -f "$INIT_PAYLOAD_PATH" ]; then
  setup_credentials
  setup_postgres
else
  echo "Skipped extracting init payload: $INIT_PAYLOAD_PATH does not exist"
fi

mkdir -p /var/log/services

SUPERVISOR_CONF=/etc/supervisor/supervisord.conf
find /etc/supervisor/ -type d -exec chmod 0770 {} +
find /etc/supervisor/ -type f -exec chmod 0660 {} +

# Start services in the background
if [ "${POSTGRES_ONLY:-}" == "true" ]; then
  sed -i "s|    - postgrest|  #  - postgrest|g" /etc/adminapi/adminapi.yaml
  sed -i "s|files = services/\*.conf base-services/\*.conf|files = base-services/\*.conf|g" $SUPERVISOR_CONF
  /init/configure-adminapi.sh
else
  sed -i "s|  #  - postgrest|    - postgrest|g" /etc/adminapi/adminapi.yaml
  sed -i "s|files = base-services/\*.conf|files = services/\*.conf base-services/\*.conf|g" $SUPERVISOR_CONF
  configure_services
fi

if [ "${AUTOSHUTDOWN_ENABLED:-}" == "true" ]; then
  enable_autoshutdown
fi

if [ "${ENVOY_ENABLED:-}" == "true" ]; then
  sed -i "s/autostart=.*/autostart=true/" /etc/supervisor/services/envoy.conf
  sed -i "s/autostart=.*/autostart=false/" /etc/supervisor/services/kong.conf
  sed -i "s/kong/envoy/" /etc/supervisor/services/group.conf
fi

if [ "${FAIL2BAN_DISABLED:-}" == "true" ]; then
  disable_fail2ban
fi

if [ "${GOTRUE_DISABLED:-}" == "true" ]; then
  sed -i "s/autostart=.*/autostart=false/" /etc/supervisor/services/gotrue.conf
  sed -i "s/autorestart=.*/autorestart=false/" /etc/supervisor/services/gotrue.conf
fi

if [ "${PLATFORM_DEPLOYMENT:-}" == "true" ]; then
  if [ "${SWAP_DISABLED:-}" != "true" ]; then
    enable_swap
  fi
  enable_lsn_checkpoint_push

  trap graceful_shutdown SIGINT
fi

touch "$CONFIGURED_FLAG_PATH"
run_prelaunch_hooks

if [ -n "${DELEGATED_INIT_LOCATION:-}" ]; then
  fetch_and_execute_delegated_payload
else
  DURATION=$(calculate_duration "$START_TIME" "$(date +%s%N)")
  echo "E: Execution time to starting supervisor: $DURATION milliseconds"
  start_supervisor
  push_lsn_checkpoint_file
fi
