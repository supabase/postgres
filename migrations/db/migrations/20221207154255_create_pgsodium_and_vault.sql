-- migrate:up

create extension if not exists pgsodium;

grant pgsodium_keyiduser to postgres with admin option;
grant pgsodium_keyholder to postgres with admin option;
grant pgsodium_keymaker  to postgres with admin option;

do $$
begin
  if not exists (select from pg_extension where extname = 'supabase_vault') then
    create extension supabase_vault;
    -- Creating the extension creates a table and creates a security label on the table.
    -- Creating the security label triggers a function that recreates these objects.
    -- Since the recreation happens in an extension script, these objects become owned by the `supabase_vault` extension.
    -- This is an issue because then we can't recreate these objects without also dropping the extension.
    -- Thus we drop the dependency on the `supabase_vault` extension for these objects.
    alter extension supabase_vault drop view pgsodium.decrypted_key;
    alter extension supabase_vault drop function pgsodium.key_encrypt_secret;
  end if;
end;
$$;

-- migrate:down
