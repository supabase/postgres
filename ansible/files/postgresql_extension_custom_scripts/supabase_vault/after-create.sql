do $$
declare
  -- It's important that the declare section doesn't have any initialization code.
  -- Any initialization should happen in the begin/end block after search_path is
  -- set to avoid search_path hijacking attacks.
  extversion text;
  search_path text;
begin
  -- Instead of setting search_path to an empty string we set it to an explicit list
  -- of pg_catalog and pg_temp. With an empty string, pg_temp is implicitly added as the
  -- first entry in search_path by Postgres. Although having pg_temp first in search_path
  -- is not always exploitable (because it's only used to lookup tables, views etc. and
  -- not functions, or procedures) it's a defence is depth measure to guard against
  -- potential later changes in the code accidentally creating a vulnerability.
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

  -- restore search_path to its previous value
  perform set_config('search_path', search_path, true);
end $$;
