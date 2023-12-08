#!/bin/bash
set -eou pipefail

if [ "${ENVOY_ENABLED:-}" != "true" ]; then
  exit
fi

ENVOY_CDS_CONF=/etc/envoy/cds.yaml
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
# "c2VydmljZV9yb2xlOnNlcnZpY2Vfa2V5" is base64-encoded "service_role:service_key".
sed -i -e "s|anon_key|$ANON_KEY|g" \
  -e "s|service_key|$SERVICE_ROLE_KEY|g" \
  -e "s|supabase_admin_key|$ADMIN_API_KEY|g" \
  -e "s|c2VydmljZV9yb2xlOnNlcnZpY2Vfa2V5|$(echo -n "service_role:$SERVICE_ROLE_KEY" | base64 --wrap 0)|g" \
  "$ENVOY_LDS_CONF"

# Update Envoy ports
sed -i "s|port_value: 80$|port_value: $ENVOY_HTTP_PORT|g" "$ENVOY_LDS_CONF"
sed -i "s|port_value: 443$|port_value: $ENVOY_HTTPS_PORT|g" "$ENVOY_LDS_CONF"
sed -i "s|port_value: 3000$|port_value: $PGRST_SERVER_PORT|g" "$ENVOY_CDS_CONF"
sed -i "s|port_value: 3001$|port_value: $PGRST_ADMIN_SERVER_PORT|g" "$ENVOY_CDS_CONF"
sed -i "s|port_value: 8085$|port_value: $ADMIN_API_PORT|g" "$ENVOY_CDS_CONF"
sed -i "s|port_value: 9999$|port_value: $GOTRUE_API_PORT|g" "$ENVOY_CDS_CONF"
