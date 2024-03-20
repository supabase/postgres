\set admin_pass `echo "${SUPABASE_ADMIN_PASSWORD:-$POSTGRES_PASSWORD}"`
\set pgrst_pass `echo "${AUTHENTICATOR_PASSWORD:-$POSTGRES_PASSWORD}"`
\set pgbouncer_pass `echo "${PGBOUNCER_PASSWORD:-$POSTGRES_PASSWORD}"`
\set auth_pass `echo "${SUPABASE_AUTH_ADMIN_PASSWORD:-$POSTGRES_PASSWORD}"`
\set storage_pass `echo "${SUPABASE_STORAGE_ADMIN_PASSWORD:-$POSTGRES_PASSWORD}"`
\set replication_pass `echo "${SUPABASE_REPLICATION_ADMIN_PASSWORD:-$POSTGRES_PASSWORD}"`
\set read_only_pass `echo "${SUPABASE_READ_ONLY_USER_PASSWORD:-$POSTGRES_PASSWORD}"`

ALTER USER supabase_admin WITH PASSWORD :'admin_pass';
ALTER USER authenticator WITH PASSWORD :'pgrst_pass';
ALTER USER pgbouncer WITH PASSWORD :'pgbouncer_pass';
ALTER USER supabase_auth_admin WITH PASSWORD :'auth_pass';
ALTER USER supabase_storage_admin WITH PASSWORD :'storage_pass';
ALTER USER supabase_replication_admin WITH PASSWORD :'replication_pass';
ALTER ROLE supabase_read_only_user WITH PASSWORD :'read_only_pass';
ALTER ROLE supabase_admin SET search_path TO "$user",public,auth,extensions;
