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

# gotrue up
curl -sSf "http://localhost:$GOTRUE_API_PORT/health"

# kong up
kong health

# pgbouncer up
printf \\0 > "/dev/tcp/localhost/$PGBOUNCER_PORT"

# fail2ban up
fail2ban-client status

# prometheus exporter up
curl -sSfI "http://localhost:$PGEXPORTER_PORT/metrics"

# vector is up
curl -sSfI "http://localhost:$VECTOR_API_PORT/health"
