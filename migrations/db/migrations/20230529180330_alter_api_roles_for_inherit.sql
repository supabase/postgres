-- migrate:up

ALTER ROLE authenticated inherit;
ALTER ROLE anon inherit;
ALTER ROLE service_role inherit;

-- migrate:down

