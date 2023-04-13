-- migrate:up
DO $$
DECLARE
  tle_exists boolean;
BEGIN
  tle_exists = (
      select count(*) = 1 
      from pg_available_extensions 
      where name = 'pg_tle'
  );

  IF tle_exists 
  THEN
    create extension if not exists pg_tle;
    drop extension if exists pg_tle;
  END IF;
END $$;

-- migrate:down

