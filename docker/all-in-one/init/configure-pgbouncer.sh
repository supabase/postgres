#!/bin/bash
set -eou pipefail

touch /var/log/services/pgbouncer.log

mkdir -p /var/run/pgbouncer
chown pgbouncer:postgres /var/run/pgbouncer

PGBOUNCER_CONF=/etc/pgbouncer/pgbouncer.ini

if [ -f "${INIT_PAYLOAD_PATH:-}" ]; then
  echo "init pgbouncer payload"
  sed -i -E "s|^# (%include /etc/pgbouncer-custom/ssl-config.ini)$|\1|g" $PGBOUNCER_CONF
fi
