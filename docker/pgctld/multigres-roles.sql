-- multigres_probe is created NOLOGIN and without a password, so nothing can
-- log in as it whatever pg_hba allows. Whoever runs the image enables it after
-- boot with ALTER ROLE multigres_probe LOGIN PASSWORD.

DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'postgres') THEN
    CREATE ROLE postgres SUPERUSER LOGIN;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'multigres_probe') THEN
    CREATE ROLE multigres_probe;
  END IF;
END $$;

ALTER ROLE multigres_probe NOLOGIN NOBYPASSRLS CONNECTION LIMIT 2;
ALTER ROLE multigres_probe SET statement_timeout = '2s';
ALTER ROLE multigres_probe SET search_path = pg_catalog, pg_temp, multigres;
ALTER ROLE multigres_probe SET pg_stat_statements.track = 'none';

-- Keep the probe's queries out of the Postgres logs, whatever log settings the
-- database has. Errors are still logged, without the query text, so a failing
-- probe stays visible.
ALTER ROLE multigres_probe SET log_statement = 'none';
ALTER ROLE multigres_probe SET log_min_duration_statement = -1;
ALTER ROLE multigres_probe SET log_duration = off;
ALTER ROLE multigres_probe SET log_min_error_statement = 'panic';
ALTER ROLE multigres_probe SET log_min_messages = 'error';
ALTER ROLE multigres_probe SET auto_explain.log_min_duration = -1;
ALTER ROLE multigres_probe SET pgaudit.log = 'none';

-- A database owner can set a database-wide default role (ALTER DATABASE ... SET
-- role), which every login then tries to switch to. Pin the probe to itself.
ALTER ROLE multigres_probe SET role = 'multigres_probe';
