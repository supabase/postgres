-- migrate:up

create extension if not exists pgsodium;

grant pgsodium_keyiduser to postgres with admin option;
grant pgsodium_keyholder to postgres with admin option;
grant pgsodium_keymaker  to postgres with admin option;

grant execute on function pgsodium.crypto_aead_det_decrypt(bytea, bytea, uuid, bytea) to service_role;
grant execute on function pgsodium.crypto_aead_det_encrypt(bytea, bytea, uuid, bytea) to service_role;
grant execute on function pgsodium.crypto_aead_det_keygen to service_role;

-- create extension if not exists supabase_vault;

-- migrate:down
