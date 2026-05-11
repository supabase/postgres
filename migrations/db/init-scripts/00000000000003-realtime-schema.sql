-- migrate:up

CREATE SCHEMA IF NOT EXISTS realtime AUTHORIZATION supabase_admin;

CREATE USER supabase_realtime_admin NOINHERIT CREATEROLE LOGIN REPLICATION;
ALTER USER supabase_realtime_admin SET search_path = public, extensions, realtime;
GRANT CREATE ON DATABASE postgres TO supabase_realtime_admin;
GRANT anon, authenticated, service_role TO supabase_realtime_admin;

-- realtime.list_changes does `SET log_min_messages = 'fatal'`;
GRANT SET ON PARAMETER log_min_messages TO supabase_realtime_admin;

do $$
begin
  if exists (select from pg_namespace where nspname = 'realtime') then
    grant usage on schema realtime to postgres, anon, authenticated, service_role;
    grant all on schema realtime to supabase_realtime_admin with grant option;
  end if;
end $$;

do $$
begin
  if exists (select from pg_namespace where nspname = 'auth') then
    GRANT USAGE ON SCHEMA auth TO supabase_realtime_admin;
    GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA auth TO supabase_realtime_admin;
  end if;
end $$;

GRANT CREATE, USAGE ON SCHEMA public TO supabase_realtime_admin;
GRANT USAGE ON SCHEMA extensions TO supabase_realtime_admin;

-- migrate:down
