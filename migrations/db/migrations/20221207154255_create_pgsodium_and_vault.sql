-- migrate:up

create extension if not exists pgsodium;

grant pgsodium_keyiduser to postgres with admin option;
grant pgsodium_keyholder to postgres with admin option;
grant pgsodium_keymaker  to postgres with admin option;

create extension if not exists vault;

-- migrate:down
