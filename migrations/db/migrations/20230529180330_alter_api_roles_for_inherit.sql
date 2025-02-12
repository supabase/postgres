-- migrate:up

ALTER ROLE authenticated inherit;
ALTER ROLE anon inherit;
ALTER ROLE service_role inherit;

GRANT pgsodium_keyholder to service_role;

-- migrate:down

