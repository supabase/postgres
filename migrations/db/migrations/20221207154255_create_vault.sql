-- migrate:up

DO $$
BEGIN
  IF EXISTS (select from pg_available_extensions where name = 'supabase_vault')
  THEN
    create extension if not exists supabase_vault;

    -- for some reason extension custom scripts aren't run during AMI build, so
    -- we manually run it here
    grant usage on schema vault to postgres with grant option;
    grant select, delete on vault.secrets, vault.decrypted_secrets to postgres with grant option;
    grant execute on function vault.create_secret, vault.update_secret, vault._crypto_aead_det_decrypt to postgres with grant option;
  END IF;
END $$;

-- migrate:down
