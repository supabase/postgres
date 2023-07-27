#!/bin/bash
set -eou pipefail

touch /var/log/services/postgrest.log

# Default in-database config
sed -i "s|pgrst_server_port|${PGRST_SERVER_PORT:-3000}|g" /etc/postgrest/base.conf
sed -i "s|pgrst_admin_server_port|${PGRST_ADMIN_SERVER_PORT:-3001}|g" /etc/postgrest/base.conf
sed -i "s|pgrst_db_schemas|${PGRST_DB_SCHEMAS:-public,storage,graphql_public}|g" /etc/postgrest/base.conf
sed -i "s|pgrst_db_extra_search_path|${PGRST_DB_SCHEMAS:-public,extensions}|g" /etc/postgrest/base.conf
sed -i "s|pgrst_db_anon_role|${PGRST_DB_ANON_ROLE:-anon}|g" /etc/postgrest/base.conf
sed -i "s|pgrst_jwt_secret|$JWT_SECRET|g" /etc/postgrest/base.conf

if [ "${DATA_VOLUME_MOUNTPOINT}" ]; then
  POSTGREST_CUSTOM_DIR="${DATA_VOLUME_MOUNTPOINT}/etc/postgrest"
  mkdir -p "${POSTGREST_CUSTOM_DIR}"
  if [ ! -f "${CONFIGURED_FLAG_PATH}" ]; then
    echo "Copying existing custom PostgREST config from /etc/postgrest/ to ${POSTGREST_CUSTOM_DIR}"
    cp -R "/etc/postgrest/." "${POSTGREST_CUSTOM_DIR}/"
  fi

  rm -rf "/etc/postgrest"
  ln -s "${POSTGREST_CUSTOM_DIR}" "/etc/postgrest"
  chown -R postgrest:postgrest "/etc/postgrest"

  chown -R postgrest:postgrest "${POSTGREST_CUSTOM_DIR}"
  chmod g+rx "${POSTGREST_CUSTOM_DIR}"
fi
  
if [ -f "${INIT_PAYLOAD_PATH:-}" ]; then
  echo "init postgrest payload"
  tar -xzvf "$INIT_PAYLOAD_PATH" -C / ./etc/postgrest/base.conf
  chown -R postgrest:postgrest /etc/postgrest
fi

PGRST_CONF=/etc/postgrest/generated.conf

/opt/supabase-admin-api optimize postgrest --destination-config-file-path $PGRST_CONF
cat /etc/postgrest/base.conf >> $PGRST_CONF
