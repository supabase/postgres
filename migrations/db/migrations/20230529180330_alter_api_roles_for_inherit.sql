-- migrate:up

ALTER ROLE authenticated inherit;
ALTER ROLE anon inherit;
ALTER ROLE service_role inherit;

DO $$
BEGIN
  -- same condition under which 20221207154255_create_pgsodium_and_vault creates pgsodium
  IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'pgsodium_keyholder')
    AND NOT EXISTS (SELECT FROM pg_available_extensions WHERE name = 'supabase_vault' AND default_version != '0.2.8')
  THEN
    GRANT pgsodium_keyholder to service_role;
  END IF;
END $$;

-- migrate:down

