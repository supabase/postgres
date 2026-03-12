-- migrate:up

-- Create a shared group role for DuckDB access.
-- Both postgres (developer/admin) and service_role (runtime API) need to run
-- DuckDB queries. We use a group role rather than cross-granting between them,
-- which mirrors the supabase_privileged_role pattern.
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'duckdb_role') THEN
    CREATE ROLE duckdb_role;
    GRANT duckdb_role TO postgres WITH ADMIN OPTION;
    GRANT duckdb_role TO service_role, supabase_admin;
  END IF;
END $$;

-- Event trigger for pg_duckdb
-- Fires on CREATE EXTENSION pg_duckdb and grants FDW usage to duckdb_role.
-- This mirrors the pattern used for pg_net and pg_cron.
CREATE OR REPLACE FUNCTION extensions.grant_pg_duckdb_access()
RETURNS event_trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_event_trigger_ddl_commands() AS ev
    JOIN pg_extension AS ext
    ON ev.objid = ext.oid
    WHERE ext.extname = 'pg_duckdb'
  )
  THEN
    GRANT USAGE ON FOREIGN DATA WRAPPER duckdb TO duckdb_role;
  END IF;
END;
$$;

CREATE EVENT TRIGGER issue_pg_duckdb_access
ON ddl_command_end
WHEN TAG IN ('CREATE EXTENSION')
EXECUTE PROCEDURE extensions.grant_pg_duckdb_access();

COMMENT ON FUNCTION extensions.grant_pg_duckdb_access IS 'Grants access to pg_duckdb';

-- Also apply immediately for existing installs where extension is already present
DO $$
BEGIN
  IF EXISTS (SELECT FROM pg_extension WHERE extname = 'pg_duckdb') THEN
    GRANT USAGE ON FOREIGN DATA WRAPPER duckdb TO duckdb_role;
  END IF;
END $$;

-- migrate:down
