-- migrate:up

-- Supabase monitoring user: no password and can only connect via localhost,
-- reads every table bypassing RLS, read-only, owns nothing. 
do $$
begin
  if not exists (select from pg_roles where rolname = 'supabase_monitor_admin') then
    create role supabase_monitor_admin with login bypassrls;
    -- necessary permissions to read almost everything
    grant pg_read_all_data, pg_monitor to supabase_monitor_admin;
    -- even though the role is read-only, these settings add friction if someone tries to takeover the role
    alter role supabase_monitor_admin set default_transaction_read_only = on;
    alter role supabase_monitor_admin set transaction_read_only = on;
    -- blocks search_path exploits
    alter role supabase_monitor_admin set search_path = pg_catalog, pg_temp;
    -- timeout settings: insurance against expensive queries disrupting projects
    alter role supabase_monitor_admin set statement_timeout = '3s';
    alter role supabase_monitor_admin set lock_timeout = '3s';
    alter role supabase_monitor_admin set idle_in_transaction_session_timeout = '3s';
  end if;
end $$;

-- disables pg_stat_statements tracking (avoids polluting pg_stat_statements).
-- The GRANT lets the exporter pass -c pg_stat_statements.track=none at login; without it the login fails
grant set on parameter pg_stat_statements.track to supabase_monitor_admin;
alter role supabase_monitor_admin set pg_stat_statements.track = 'none';

-- disable auto_explain (avoids noisy logs)
alter role supabase_monitor_admin set auto_explain.log_min_duration = -1;

-- needed to change temp_file_limit for monitor. Avoids creating large temp files on user projects
grant set on parameter temp_file_limit to supabase_monitor_admin;

-- prevent database-wide `role` changes (ALTER DATABASE / ALTER ROLE ALL ... SET role) from impacting the role
alter role supabase_monitor_admin set role = 'supabase_monitor_admin';

-- allows role to read postgresql.conf and postgresql.auto.conf (ALTER SYSTEM). Necessary for checking if DB is in read-only state
grant select on pg_catalog.pg_file_settings to supabase_monitor_admin;
grant execute on function pg_catalog.pg_show_all_file_settings() to supabase_monitor_admin;

-- migrate:down
