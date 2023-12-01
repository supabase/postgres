#!/bin/bash
set -eou pipefail

ENVOY_LDS_CONF=/etc/envoy/lds.yaml
touch /var/log/services/envoy.log

/usr/local/bin/configure-shim.sh /dist/envoy /opt/envoy

if [ "$DATA_VOLUME_MOUNTPOINT" ]; then
  ENVOY_CUSTOM_DIR="${DATA_VOLUME_MOUNTPOINT}/etc/envoy"
  mkdir -p "$ENVOY_CUSTOM_DIR"
  if [ ! -f "$CONFIGURED_FLAG_PATH" ]; then
    echo "Copying existing custom envoy config from /etc/envoy/ to ${ENVOY_CUSTOM_DIR}"
    cp -R "/etc/envoy/." "${ENVOY_CUSTOM_DIR}/"
  fi

  rm -rf "/etc/envoy"
  ln -s "$ENVOY_CUSTOM_DIR" "/etc/envoy"
  chown -R adminapi:adminapi "/etc/envoy"

  chown -R adminapi:adminapi "$ENVOY_CUSTOM_DIR"
  chmod g+rx "$ENVOY_CUSTOM_DIR"
fi

if [ -f "${INIT_PAYLOAD_PATH:-}" ]; then
  echo "init envoy payload"
  tar -xzvf "$INIT_PAYLOAD_PATH" -C / ./etc/envoy/
  chown -R adminapi:adminapi /etc/envoy
fi

# Inject project specific configuration
sed -i -e "s|anon_key|$ANON_KEY|g" \
  -e "s|service_key|$SERVICE_ROLE_KEY|g" \
  -e "s|supabase_admin_key|$ADMIN_API_KEY|g" \
  "$ENVOY_LDS_CONF"

# Update Envoy ports
sed -i "s|:80 |:$ENVOY_HTTP_PORT |g" "$ENVOY_LDS_CONF"
sed -i "s|:443 |:$ENVOY_HTTPS_PORT |g" "$ENVOY_LDS_CONF"
sed -i "s|:3000 |:$PGRST_SERVER_PORT |g" "$ENVOY_LDS_CONF"
sed -i "s|:3001 |:$PGRST_ADMIN_SERVER_PORT |g" "$ENVOY_LDS_CONF"
sed -i "s|:8085 |:$ADMIN_API_PORT |g" "$ENVOY_LDS_CONF"
sed -i "s|:9999 |:$GOTRUE_API_PORT |g" "$ENVOY_LDS_CONF"
