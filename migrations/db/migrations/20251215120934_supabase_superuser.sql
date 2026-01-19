-- migrate:up
do $$
begin
  if not exists (select from pg_roles where rolname = 'supabase_superuser') then
    create role supabase_superuser;
    grant supabase_superuser to postgres, supabase_etl_admin;
  end if;
end $$;

-- migrate:down
