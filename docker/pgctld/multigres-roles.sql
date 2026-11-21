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
