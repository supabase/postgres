#!/bin/bash

set -e

SCRIPT_DIR=$(dirname -- "$0")
ls -la "$SCRIPT_DIR"
tar -xzf "$SCRIPT_DIR/pg_upgrade_scripts.tar.gz" -C "$SCRIPT_DIR"

mkdir -p /tmp/persistent
cp "$SCRIPT_DIR/pg_upgrade_bin.tar.gz" /tmp/persistent

pg_bindir=$(pg_config --bindir)
export PATH=$pg_bindir:$PATH

# The cluster has to live where initiate.sh upgrades it in place (see PGDATA in .env)
sed -i "s|^data_directory = .*|data_directory = '/data/pgdata'|" /etc/postgresql/postgresql.conf

sed -i "s/|--version//g" /usr/local/bin/docker-entrypoint.sh
/usr/local/bin/docker-entrypoint.sh postgres --version || true

su postgres -c "$pg_bindir/pg_ctl start -o '-c config_file=/etc/postgresql/postgresql.conf' -l /tmp/postgres.log"

# todo: sleep infinity instead of all this
RECEIVED_EXIT_SIGNAL=false
trap 'RECEIVED_EXIT_SIGNAL=true' SIGINT SIGTERM SIGUSR1
while ! ((RECEIVED_EXIT_SIGNAL)); do
	sleep 5
done
