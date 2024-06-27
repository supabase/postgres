-- migrate:up
revoke supabase_auth_admin from postgres;
revoke create on schema auth from postgres;
revoke all on auth.schema_migrations from dashboard_user, postgres;

-- migrate:down
