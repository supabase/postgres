-- migrate:up

-- Supabase monitoring user: no password and can only connect via localhost,
-- reads every table bypassing RLS, read-only, owns nothing.
do $$
begin
  if not exists (select from pg_roles where rolname = 'supabase_monitor_admin') then
    create role supabase_monitor_admin with login bypassrls;
    grant pg_read_all_data, pg_monitor to supabase_monitor_admin;
    alter role supabase_monitor_admin set default_transaction_read_only = on;
    alter role supabase_monitor_admin set transaction_read_only = on;
    alter role supabase_monitor_admin set search_path = pg_catalog, pg_temp;
    alter role supabase_monitor_admin set statement_timeout = '3s';
    alter role supabase_monitor_admin set lock_timeout = '3s';
    alter role supabase_monitor_admin set idle_in_transaction_session_timeout = '3s';
  end if;
end $$;

-- migrate:down
