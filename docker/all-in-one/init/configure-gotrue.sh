#!/bin/bash
set -eou pipefail

touch /var/log/services/gotrue.log

sed -i "s|gotrue_api_host|${GOTRUE_API_HOST:-0.0.0.0}|g" /etc/gotrue.env
sed -i "s|gotrue_site_url|$GOTRUE_SITE_URL|g" /etc/gotrue.env
sed -i "s|gotrue_jwt_secret|$JWT_SECRET|g" /etc/gotrue.env

if [ "${DATA_VOLUME_MOUNTPOINT}" ]; then
  GOTRUE_CUSTOM_CONFIG_FILE_PATH="${DATA_VOLUME_MOUNTPOINT}/etc/gotrue.env"
  if [ ! -f "${CONFIGURED_FLAG_PATH}" ]; then
    echo "Copying existing GoTrue config from /etc/gotrue.env to ${GOTRUE_CUSTOM_CONFIG_FILE_PATH}"
    cp "/etc/gotrue.env" "${GOTRUE_CUSTOM_CONFIG_FILE_PATH}"
  fi

  rm -f "/etc/gotrue.env"
  ln -s "${GOTRUE_CUSTOM_CONFIG_FILE_PATH}" "/etc/gotrue.env"
  chown -R adminapi:adminapi "/etc/gotrue.env"

  chown -R adminapi:adminapi "${GOTRUE_CUSTOM_CONFIG_FILE_PATH}"
  chmod g+rx "${GOTRUE_CUSTOM_CONFIG_FILE_PATH}"
fi

if [ -f "${INIT_PAYLOAD_PATH:-}" ]; then
  echo "init gotrue payload"
  tar -xzvf "$INIT_PAYLOAD_PATH" -C / ./etc/gotrue.env
  chown -R adminapi:adminapi /etc/gotrue.env
fi
