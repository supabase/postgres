#!/bin/bash
set -eou pipefail

touch /var/log/services/gotrue.log

sed -i "s|gotrue_api_host|${GOTRUE_API_HOST:-0.0.0.0}|g" /etc/gotrue.env
sed -i "s|gotrue_site_url|$GOTRUE_SITE_URL|g" /etc/gotrue.env
sed -i "s|gotrue_jwt_secret|$JWT_SECRET|g" /etc/gotrue.env

if [ -f "${INIT_PAYLOAD_PATH:-}" ]; then
  echo "init gotrue payload"
  tar -xzvf "$INIT_PAYLOAD_PATH" -C / ./etc/gotrue.env
  chown -R adminapi:adminapi /etc/gotrue.env
fi
