-- migrate:up

DO $$
DECLARE
  pgsodium_exists boolean;
  vault_exists boolean;
BEGIN
  pgsodium_exists = (
    select count(*) = 1 
    from pg_available_extensions 
    where name = 'pgsodium'
  );
  
  vault_exists = (
      select count(*) = 1 
      from pg_available_extensions 
      where name = 'supabase_vault'
  );

  IF pgsodium_exists 
  THEN
    create extension if not exists pgsodium;

    grant pgsodium_keyiduser to postgres with admin option;
    grant pgsodium_keyholder to postgres with admin option;
    grant pgsodium_keymaker  to postgres with admin option;

    grant execute on function pgsodium.crypto_aead_det_decrypt(bytea, bytea, uuid, bytea) to service_role;
    grant execute on function pgsodium.crypto_aead_det_encrypt(bytea, bytea, uuid, bytea) to service_role;
    grant execute on function pgsodium.crypto_aead_det_keygen to service_role;

    IF vault_exists
    THEN
      create extension if not exists supabase_vault;
    END IF;
  END IF;
END $$;

-- migrate:down
