do $$
declare
  extversion text;
  search_path text;
begin
  search_path := current_setting('search_path');
  perform set_config('search_path', 'pg_catalog, pg_temp', true);

  select e.extversion into extversion from pg_extension e where e.extname = 'supabase_vault';

  if extversion != '0.2.8' then
    grant usage on schema vault to postgres with grant option;
    grant select, delete, truncate, references on vault.secrets, vault.decrypted_secrets to postgres with grant option;
    grant execute on function vault.create_secret, vault.update_secret, vault._crypto_aead_det_decrypt to postgres with grant option;

    -- service_role used to be able to manage secrets in Vault <=0.2.8 because it had privileges to pgsodium functions
    grant usage on schema vault to service_role;
    grant select, delete on vault.secrets, vault.decrypted_secrets to service_role;
    grant execute on function vault.create_secret, vault.update_secret, vault._crypto_aead_det_decrypt to service_role;
  end if;

  perform set_config('search_path', search_path, true);
end $$;
