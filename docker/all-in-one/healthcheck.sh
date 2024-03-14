#!/bin/bash
set -eou pipefail

# database up
pg_isready -U postgres -h localhost -p 5432

if [ -f "/tmp/init.json" ]; then
  ADMIN_API_KEY=${ADMIN_API_KEY:-$(jq -r '.["supabase_admin_key"]' /tmp/init.json)}
fi

# adminapi up
if [ -d "$ADMIN_API_CERT_DIR" ]; then
  curl -sSkf "https://localhost:$ADMIN_API_PORT/health" -H "apikey: $ADMIN_API_KEY"
else
  curl -sSf "http://localhost:$ADMIN_API_PORT/health" -H "apikey: $ADMIN_API_KEY"
fi

if [ "${POSTGRES_ONLY:-}" ]; then
  exit 0
fi

# postgrest up
curl -sSfI "http://localhost:$PGRST_ADMIN_SERVER_PORT/ready"

if [ "${GOTRUE_DISABLED:-}" != "true" ]; then
  # gotrue up
  curl -sSf "http://localhost:$GOTRUE_API_PORT/health"
fi

if [ "${ENVOY_ENABLED:-}" == "true" ]; then
  # envoy up
  curl -sSfI "http://localhost:$ENVOY_HTTP_PORT/health"
else
  # kong up
  kong health
fi

# pgbouncer up
printf \\0 > "/dev/tcp/localhost/$PGBOUNCER_PORT"

if [ "${FAIL2BAN_DISABLED:-}" != "true" ]; then
  # fail2ban up
  fail2ban-client status
fi

# prometheus exporter up
curl -sSfI "http://localhost:$PGEXPORTER_PORT/metrics"

# vector is up (if starting logflare)
# TODO: make this non-conditional once we set up local logflare for testinfra
if [ -n "${LOGFLARE_API_KEY:-}" ]; then
  curl -sSfI "http://localhost:$VECTOR_API_PORT/health"
fi
