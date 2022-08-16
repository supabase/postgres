create schema if not exists pgsodium;
create extension if not exists pgsodium with schema pgsodium cascade;

grant pgsodium_keyiduser to postgres with admin option;
grant pgsodium_keyholder to postgres with admin option;
grant pgsodium_keymaker  to postgres with admin option;
