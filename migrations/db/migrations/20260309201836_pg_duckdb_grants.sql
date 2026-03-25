-- migrate:up

-- Create a shared group role for DuckDB access.
-- Both postgres (developer/admin) and service_role (runtime API) need to run
-- DuckDB queries. We use a group role rather than cross-granting between them,
-- which mirrors the supabase_privileged_role pattern.
--
-- The FDW grant (GRANT USAGE ON FOREIGN DATA WRAPPER duckdb TO duckdb_role) is
-- handled by ansible/files/postgresql_extension_custom_scripts/pg_duckdb/after-create.sql
-- rather than an event trigger, following the established pattern for postgres_fdw etc.
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'duckdb_role') THEN
    CREATE ROLE duckdb_role;
    GRANT duckdb_role TO postgres WITH ADMIN OPTION;
    GRANT duckdb_role TO service_role, supabase_admin;
  END IF;
END $$;

-- migrate:down
