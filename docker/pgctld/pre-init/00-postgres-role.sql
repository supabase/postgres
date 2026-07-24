-- docker-entrypoint.sh creates a postgres superuser role when POSTGRES_USER != postgres.
-- pgctld init does not replicate this behaviour, so we create it here before the
-- supabase init scripts run (they reference the postgres role at line 39 of
-- 00000000000000-initial-schema.sql).
CREATE USER postgres SUPERUSER;
