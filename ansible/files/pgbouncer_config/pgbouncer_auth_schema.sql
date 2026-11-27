CREATE USER pgbouncer;

REVOKE ALL PRIVILEGES ON SCHEMA public FROM pgbouncer;

CREATE SCHEMA pgbouncer AUTHORIZATION pgbouncer;

CREATE OR REPLACE FUNCTION pgbouncer.get_auth(p_usename TEXT)
RETURNS TABLE(username TEXT, password TEXT)
LANGUAGE plpgsql
SET search_path = ''
SECURITY DEFINER
AS $$
BEGIN
    RAISE DEBUG 'PgBouncer auth request: %', p_usename;

    RETURN QUERY
    SELECT
        rolname::TEXT,
        CASE WHEN rolvaliduntil < now()
            THEN NULL
            ELSE rolpassword::TEXT
        END
    FROM pg_authid
    WHERE rolname = $1 AND rolcanlogin;
END;
$$;

REVOKE ALL ON FUNCTION pgbouncer.get_auth(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION pgbouncer.get_auth(TEXT) TO pgbouncer;
