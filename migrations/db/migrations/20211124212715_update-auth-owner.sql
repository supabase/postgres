-- migrate:up

-- update owner for auth.uid, auth.role and auth.email functions
-- revoke clears grants to postgres that earlier migrations add on a re-run
DO $$
BEGIN
    ALTER FUNCTION auth.uid owner to supabase_auth_admin;
    REVOKE ALL ON FUNCTION auth.uid FROM postgres;
EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'Error encountered when changing owner of auth.uid to supabase_auth_admin';
END $$;

DO $$
BEGIN
    ALTER FUNCTION auth.role owner to supabase_auth_admin;
    REVOKE ALL ON FUNCTION auth.role FROM postgres;
EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'Error encountered when changing owner of auth.role to supabase_auth_admin';
END $$;

DO $$
BEGIN
    ALTER FUNCTION auth.email owner to supabase_auth_admin;
    REVOKE ALL ON FUNCTION auth.email FROM postgres;
EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'Error encountered when changing owner of auth.email to supabase_auth_admin';
END $$;
-- migrate:down
