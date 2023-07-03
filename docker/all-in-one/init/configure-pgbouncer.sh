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

if [ "${DATA_VOLUME_MOUNTPOINT}" ]; then
  /opt/supabase-admin-api optimize pgbouncer --destination-config-file-path /etc/pgbouncer-custom/generated-optimizations.ini

  # Preserve pgbouncer configs across restarts
  PGBOUNCER_DIR="${DATA_VOLUME_MOUNTPOINT}/etc/pgbouncer"
  PGBOUNCER_CUSTOM_DIR="${DATA_VOLUME_MOUNTPOINT}/etc/pgbouncer-custom"

  mkdir -p "${PGBOUNCER_DIR}"
  mkdir -p "${PGBOUNCER_CUSTOM_DIR}"

  if [ ! -f "${CONFIGURED_FLAG_PATH}" ]; then
    echo "Copying existing custom pgbouncer config from /etc/pgbouncer-custom to ${PGBOUNCER_CUSTOM_DIR}"
    cp -R "/etc/pgbouncer-custom/." "${PGBOUNCER_CUSTOM_DIR}/"
    cp -R "/etc/pgbouncer/." "${PGBOUNCER_DIR}/"
  fi

  rm -rf "/etc/pgbouncer-custom"
  ln -s "${PGBOUNCER_CUSTOM_DIR}" "/etc/pgbouncer-custom"
  chown -R pgbouncer:pgbouncer "/etc/pgbouncer-custom"
  chown -R pgbouncer:pgbouncer "${PGBOUNCER_CUSTOM_DIR}"
  chmod -R g+rx "${PGBOUNCER_CUSTOM_DIR}"

  rm -rf "/etc/pgbouncer"
  ln -s "${PGBOUNCER_DIR}" "/etc/pgbouncer"
  chown -R pgbouncer:pgbouncer "/etc/pgbouncer"
  chown -R pgbouncer:pgbouncer "${PGBOUNCER_DIR}"
  chmod -R g+rx "${PGBOUNCER_DIR}"
fi
