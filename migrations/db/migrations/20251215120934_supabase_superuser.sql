-- migrate:up
create role supabase_superuser;
grant supabase_superuser to postgres, supabase_etl_admin;

-- migrate:down
