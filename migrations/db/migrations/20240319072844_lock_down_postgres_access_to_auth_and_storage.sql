-- migrate:up
revoke supabase_auth_admin from postgres;
revoke all on table auth.schema_migrations from postgres;
grant select on table auth.schema_migrations to postgres;

revoke supabase_storage_admin from postgres;
revoke all on table storage.migrations from postgres;
grant select on table storage.migrations to postgres;

-- migrate:down
