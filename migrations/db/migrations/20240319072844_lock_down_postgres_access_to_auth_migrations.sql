-- migrate:up
revoke supabase_auth_admin from postgres;

-- migrate:down
