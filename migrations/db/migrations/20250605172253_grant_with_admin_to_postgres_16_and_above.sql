-- migrate:up
DO $$
DECLARE
  major_version INT;
BEGIN
  SELECT current_setting('server_version_num')::INT / 10000 INTO major_version;

  IF major_version >= 16 THEN
    GRANT anon, authenticated, service_role TO postgres WITH ADMIN OPTION;
  END IF;
END $$;

-- migrate:down
