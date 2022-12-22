-- migrate:up

grant select on all tables in schema information_schema to supabase_auth_admin;

-- migrate:down
