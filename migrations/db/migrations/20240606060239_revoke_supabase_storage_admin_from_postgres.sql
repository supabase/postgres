-- migrate:up
revoke supabase_storage_admin from postgres;

-- migrate:down
