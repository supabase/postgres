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

-- The monitor's own queries must not show up in the customer's
-- pg_stat_statements. Off by default at login, and the role may also pass
-- `-c pg_stat_statements.track=none` itself (like postgres_exporter does),
-- which otherwise fails with "permission denied to set parameter" because
-- the parameter is superuser-only. Same for temp_file_limit, which the
-- fleet's postgres_exporter passes outside prod; the default is unlimited,
-- so being able to set it gives the role nothing. Outside the
-- `if not exists` block so that a role created by an earlier revision of
-- this migration also gets them.
alter role supabase_monitor_admin set pg_stat_statements.track = 'none';
grant set on parameter pg_stat_statements.track to supabase_monitor_admin;
grant set on parameter temp_file_limit to supabase_monitor_admin;

-- The per-role default_transaction_read_only = on above hides the
-- system-wide value, so `show default_transaction_read_only` cannot tell the
-- monitor whether the project has been put into read-only mode
-- (manage_readonly_mode.sh: ALTER SYSTEM SET default_transaction_read_only).
-- pg_file_settings shows the configuration files' values, including
-- postgresql.auto.conf. initdb revokes the view and its function from
-- PUBLIC; the view calls the function as the caller, so both grants are
-- needed (SELECT also comes with pg_read_all_data, but is granted explicitly
-- so this does not depend on that membership). Nothing secret: pg_monitor
-- already reads every live setting.
--
-- Deliberately NOT granted: pg_hba_file_rules() and pg_ident_file_mappings().
-- They would show who may connect from where and how; pg_read_all_data
-- gives SELECT on the views, but without EXECUTE on the functions reading
-- them still fails with "permission denied".
grant select on pg_catalog.pg_file_settings to supabase_monitor_admin;
grant execute on function pg_catalog.pg_show_all_file_settings() to supabase_monitor_admin;

-- migrate:down
