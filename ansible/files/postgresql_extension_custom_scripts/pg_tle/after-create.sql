grant pgtle_admin to postgres;

do $$
begin
  -- Runs iff pg_tle is created after *_add_supabase_superuser.sql is run.
  if exists (select from pg_roles where rolname = 'supabase_superuser') then
    grant supabase_superuser to pgtle_admin;
  end if;
end $$;
