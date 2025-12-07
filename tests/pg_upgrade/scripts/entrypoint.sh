#!/bin/bash

set -e 

SCRIPT_DIR=$(dirname -- "$0";)

ls -la "$SCRIPT_DIR"

tar -xzf "${SCRIPT_DIR}/pg_upgrade_scripts.tar.gz" -C "${SCRIPT_DIR}"

mkdir -p /tmp/persistent
cp "$SCRIPT_DIR/pg_upgrade_bin.tar.gz" /tmp/persistent

export PATH="$(pg_config --bindir):$PATH"

sed -i "s/|--version//g" /usr/local/bin/docker-entrypoint.sh
/usr/local/bin/docker-entrypoint.sh postgres --version || true

su postgres -c "$(pg_config --bindir)/pg_ctl start -o '-c config_file=/etc/postgresql/postgresql.conf' -l /tmp/postgres.log"

RECEIVED_EXIT_SIGNAL=false
trap 'RECEIVED_EXIT_SIGNAL=true' SIGINT SIGTERM SIGUSR1
while ! ((RECEIVED_EXIT_SIGNAL)); do
    sleep 5
done
