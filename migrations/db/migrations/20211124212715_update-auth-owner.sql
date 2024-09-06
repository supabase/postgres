-- migrate:up

-- update owner for auth.uid, auth.role and auth.email functions
DO $$
BEGIN
    ALTER FUNCTION auth.uid owner to supabase_auth_admin;
    ALTER FUNCTION auth.role owner to supabase_auth_admin;
    ALTER FUNCTION auth.email owner to supabase_auth_admin;
EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'Error encountered when changing owner of auth.uid, auth.role or auth.email to supabase_auth_admin';
END $$;
-- migrate:down
