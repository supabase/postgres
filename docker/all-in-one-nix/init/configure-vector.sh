#!/bin/bash
set -eou pipefail

VECTOR_CONF=/etc/vector/vector.yaml
touch /var/log/services/vector.log

if [ -f "${INIT_PAYLOAD_PATH:-}" ]; then
  echo "init vector payload"
  tar -xzvf "$INIT_PAYLOAD_PATH" -C /etc/vector/ --strip-components 2 ./tmp/init.json
  PROJECT_REF=$(jq -r '.["project_ref"]' /etc/vector/init.json)
  LOGFLARE_DB_SOURCE=$(jq -r '.["logflare_db_source"]' /etc/vector/init.json)
  LOGFLARE_GOTRUE_SOURCE=$(jq -r '.["logflare_gotrue_source"]' /etc/vector/init.json)
  LOGFLARE_POSTGREST_SOURCE=$(jq -r '.["logflare_postgrest_source"]' /etc/vector/init.json)
  LOGFLARE_PGBOUNCER_SOURCE=$(jq -r '.["logflare_pgbouncer_source"]' /etc/vector/init.json)
  LOGFLARE_PITR_ERRORS_SOURCE=$(jq -r '.["logflare_pitr_errors_source"]' /etc/vector/init.json)
  LOGFLARE_API_KEY=$(jq -r '.["logflare_api_key"]' /etc/vector/init.json)
fi

# Exit early if not starting logflare
if [ -z "${LOGFLARE_API_KEY:-}" ]; then
  echo "Skipped starting vector: missing LOGFLARE_API_KEY"
  exit 0
fi

# Add vector to support both base-services and services config
cat <<EOF > /etc/supervisor/services/vector.conf

[program:vector]
command=/usr/bin/vector --config-yaml /etc/vector/vector.yaml
user=root
autorestart=true
stdout_logfile=/var/log/services/vector.log
redirect_stderr=true
stdout_logfile_maxbytes=10MB
priority=250

EOF

VECTOR_API_PORT=${VECTOR_API_PORT:-9001}
PROJECT_REF=${PROJECT_REF:-default}
LOGFLARE_HOST=${LOGFLARE_HOST:-api.logflare.app}
LOGFLARE_DB_SOURCE=${LOGFLARE_DB_SOURCE:-postgres.logs}
LOGFLARE_GOTRUE_SOURCE=${LOGFLARE_GOTRUE_SOURCE:-gotrue.logs.prod}
LOGFLARE_POSTGREST_SOURCE=${LOGFLARE_POSTGREST_SOURCE:-postgREST.logs.prod}
LOGFLARE_PGBOUNCER_SOURCE=${LOGFLARE_PGBOUNCER_SOURCE:-pgbouncer.logs.prod}
LOGFLARE_PITR_ERRORS_SOURCE=${LOGFLARE_PITR_ERRORS_SOURCE:-pitr_errors.logs.prod}

sed -i "s|{{ .ApiPort }}|$VECTOR_API_PORT|g" $VECTOR_CONF
sed -i "s|{{ .ProjectRef }}|$PROJECT_REF|g" $VECTOR_CONF
sed -i "s|{{ .LogflareHost }}|$LOGFLARE_HOST|g" $VECTOR_CONF
sed -i "s|{{ .ApiKey }}|$LOGFLARE_API_KEY|g" $VECTOR_CONF
sed -i "s|{{ .DbSource }}|$LOGFLARE_DB_SOURCE|g" $VECTOR_CONF
sed -i "s|{{ .GotrueSource }}|$LOGFLARE_GOTRUE_SOURCE|g" $VECTOR_CONF
sed -i "s|{{ .PostgrestSource }}|$LOGFLARE_POSTGREST_SOURCE|g" $VECTOR_CONF
sed -i "s|{{ .PgbouncerSource }}|$LOGFLARE_PGBOUNCER_SOURCE|g" $VECTOR_CONF
sed -i "s|{{ .PitrErrorsSource }}|$LOGFLARE_PITR_ERRORS_SOURCE|g" $VECTOR_CONF
