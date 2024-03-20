-- migrate:up
revoke supabase_auth_admin from postgres;
revoke all on table auth.schema_migrations from postgres;
grant select on table auth.schema_migrations to postgres;

-- migrate:down
