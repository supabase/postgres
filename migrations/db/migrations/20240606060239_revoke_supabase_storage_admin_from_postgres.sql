-- migrate:up
revoke supabase_storage_admin from postgres;
revoke all on storage.migrations from anon, authenticated, service_role, postgres;

-- migrate:down
