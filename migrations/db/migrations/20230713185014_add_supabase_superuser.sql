-- migrate:up

do $$
begin
  if not exists (select from pg_roles where rolname = 'supabase_superuser') then
    create role supabase_superuser;
    grant pg_monitor, pg_signal_backend to supabase_superuser;
    grant supabase_superuser to postgres;
    -- These privs are redundant.
    revoke pg_monitor, pg_signal_backend from postgres;

    -- Runs iff this migration runs after pg_tle's after-create.sql is run.
    if exists (select from pg_roles where rolname = 'pgtle_admin') then
      grant supabase_superuser to pgtle_admin;
    end if;
  end if;
end $$;

-- migrate:down

