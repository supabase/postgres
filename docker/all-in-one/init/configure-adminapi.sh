#!/bin/bash
set -eou pipefail

ADMIN_API_CONF=/etc/adminapi/adminapi.yaml
touch /var/log/services/adminapi.log

ADMINAPI_CUSTOM_DIR="${DATA_VOLUME_MOUNTPOINT}/etc/adminapi"
if [ ! -f "${CONFIGURED_FLAG_PATH}" ]; then
  echo "Copying existing custom adminapi config from /etc/adminapi to ${ADMINAPI_CUSTOM_DIR}"
  cp -R "/etc/adminapi/." "${ADMINAPI_CUSTOM_DIR}/"
fi

rm -rf "/etc/adminapi"
ln -s "${ADMINAPI_CUSTOM_DIR}" "/etc/adminapi"
chown -R adminapi:adminapi "/etc/adminapi"
chown -R adminapi:adminapi "${ADMINAPI_CUSTOM_DIR}"
chmod g+rx "${ADMINAPI_CUSTOM_DIR}"

if [ -f "${INIT_PAYLOAD_PATH:-}" ]; then
  echo "init adminapi payload"
  tar -xzvf "$INIT_PAYLOAD_PATH" -C / ./etc/adminapi/adminapi.yaml
  chown adminapi:adminapi ./etc/adminapi/adminapi.yaml

  mkdir -p $ADMIN_API_CERT_DIR
  tar -xzvf "$INIT_PAYLOAD_PATH" -C $ADMIN_API_CERT_DIR --strip-components 2 ./ssl/server.crt
  tar -xzvf "$INIT_PAYLOAD_PATH" -C $ADMIN_API_CERT_DIR --strip-components 2 ./ssl/server.key
  chown -R adminapi:root $ADMIN_API_CERT_DIR
  chmod 700 -R $ADMIN_API_CERT_DIR
else
  PROJECT_REF=${PROJECT_REF:-default}
  PGBOUNCER_PASSWORD=${PGBOUNCER_PASSWORD:-$POSTGRES_PASSWORD}
  SUPABASE_URL=${SUPABASE_URL:-https://api.supabase.io/system}
  REPORTING_TOKEN=${REPORTING_TOKEN:-token}

  sed -i "s|{{ .JwtSecret }}|$JWT_SECRET|g" $ADMIN_API_CONF
  sed -i "s|{{ .PgbouncerPassword }}|$PGBOUNCER_PASSWORD|g" $ADMIN_API_CONF
  sed -i "s|{{ .ProjectRef }}|$PROJECT_REF|g" $ADMIN_API_CONF
  sed -i "s|{{ .SupabaseUrl }}|$SUPABASE_URL|g" $ADMIN_API_CONF
  sed -i "s|{{ .ReportingToken }}|$REPORTING_TOKEN|g" $ADMIN_API_CONF
fi

# Allow adminapi to write to /etc and manage Postgres configs
chmod g+w /etc
chmod -R 0775 /etc/postgresql
chmod -R 0775 /etc/postgresql-custom

# Update api port
sed -i "s|^port: .*$|port: ${ADMIN_API_PORT:-8085}|g" $ADMIN_API_CONF
