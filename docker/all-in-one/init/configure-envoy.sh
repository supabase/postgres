#!/bin/bash
set -eou pipefail

ENVOY_CONF=/etc/envoy/envoy.yml
touch /var/log/services/envoy.log




if [ -f "${INIT_PAYLOAD_PATH:-}" ]; then
  echo "init envoy payload"
  # Setup ssl termination
  tar -xzvf "$INIT_PAYLOAD_PATH" -C / ./etc/envoy/
  chown -R adminapi:adminapi ./etc/envoy/envoy.yml
  #chown -R adminapi:adminapi ./etc/envoy/*pem
  #echo "ssl_cipher_suite = intermediate" >> /etc/envoy/kong.conf
  #echo "ssl_cert = /etc/kong/fullChain.pem" >> /etc/kong/kong.conf
  #echo "ssl_cert_key = /etc/kong/privKey.pem" >> /etc/kong/kong.conf
else
  # Default gateway config
  export KONG_DNS_ORDER=LAST,A,CNAME
  export KONG_PROXY_ERROR_LOG=syslog:server=unix:/dev/log
  export KONG_ADMIN_ERROR_LOG=syslog:server=unix:/dev/log
fi

# Inject project specific configuration
sed -i -e "s|anon_key|$ANON_KEY|g" \
  -e "s|service_key|$SERVICE_ROLE_KEY|g" \
  -e "s|supabase_admin_key|$ADMIN_API_KEY|g" \
  $ENVOY_CONF

# Update envoy ports
sed -i "s|80 |:$KONG_HTTP_PORT |g" /etc/envoy/envoy.yml
sed -i "s|443 |:$KONG_HTTPS_PORT |g" /etc/envoy/envoy.yml
