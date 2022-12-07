-- migrate:up

create extension pgsodium;

grant pgsodium_keyiduser to postgres with admin option;
grant pgsodium_keyholder to postgres with admin option;
grant pgsodium_keymaker  to postgres with admin option;

create extension supabase_vault;

-- migrate:down
