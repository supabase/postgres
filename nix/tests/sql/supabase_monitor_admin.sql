-- supabase_monitor_admin: passwordless, read-only monitoring role
-- (migrations/db/migrations/20261113000000_supabase_monitor_admin.sql)

-- desired attributes: 
-- - login
-- - no password
-- - bypassrls
-- - no connection limit
-- - nothing else
select rolsuper, rolinherit, rolcreaterole, rolcreatedb, rolcanlogin,
       rolreplication, rolbypassrls, rolconnlimit, rolpassword is null as no_password
from pg_authid where rolname = 'supabase_monitor_admin';

-- per-role settings:
     -- read-only by default
     -- search_path pg_catalog + pg_temp
     -- timeouts: statement_timeout, lock_timeout, idle_in_transaction_session_timeout
     -- not tracked by pg_stat_statements
     -- not logged by auto_explain
     -- session role pinned to self
select unnest(rolconfig) as setting from pg_roles where rolname = 'supabase_monitor_admin' order by 1;

-- memberships: exactly pg_monitor and pg_read_all_data
select roleid::regrole::text as role, admin_option
from pg_auth_members where member = 'supabase_monitor_admin'::regrole order by 1;

-- nobody is a member of it
select count(*) from pg_auth_members where roleid = 'supabase_monitor_admin'::regrole;

-- owns nothing
select count(*) from pg_shdepend
where refclassid = 'pg_authid'::regclass
  and refobjid = 'supabase_monitor_admin'::regrole
  and deptype = 'o';

-- object-level privileges: 
     -- exactly SET on pg_stat_statements.track and
     -- temp_file_limit (not ALTER SYSTEM)
     -- SELECT on the pg_file_settings view and EXECUTE on pg_show_all_file_settings()
select pg_describe_object(classid, objid, objsubid) as object
from pg_shdepend
where refclassid = 'pg_authid'::regclass
  and refobjid = 'supabase_monitor_admin'::regrole
  and deptype = 'a'
order by 1;

-- object-level privileges: 
     -- exactly SET on pg_stat_statements.track and
     -- temp_file_limit
     -- cannot alter system
select p as parameter,
       has_parameter_privilege('supabase_monitor_admin', p, 'SET') as can_set,
       has_parameter_privilege('supabase_monitor_admin', p, 'ALTER SYSTEM') as can_alter_system
from (values ('pg_stat_statements.track'), ('temp_file_limit')) t(p)
order by 1;

-- can read pg_file_settings; reading pg_config, pg_hba_file_rules and pg_ident_file_mappings fails (no EXECUTE on their functions)
select v as object,
       has_table_privilege('supabase_monitor_admin', 'pg_catalog.' || v, 'SELECT') as can_select,
       has_function_privilege('supabase_monitor_admin', 'pg_catalog.' || f, 'EXECUTE') as can_execute
from (values ('pg_config', 'pg_config()'),
             ('pg_file_settings', 'pg_show_all_file_settings()'),
             ('pg_hba_file_rules', 'pg_hba_file_rules()'),
             ('pg_ident_file_mappings', 'pg_ident_file_mappings()')) t(v, f)
order by 1;

-- no CREATE on the database
select has_database_privilege('supabase_monitor_admin', current_database(), 'CREATE');

-- reads every table regardless of RLS, but cannot write;
-- SET ROLE pg_read_all_data drops BYPASSRLS, so the count becomes 0
create table public.monitor_probe (id int);
insert into public.monitor_probe values (1), (2);
alter table public.monitor_probe enable row level security;
alter table public.monitor_probe force row level security;
alter table public.monitor_probe owner to postgres;
set session authorization supabase_monitor_admin;
select count(*) from public.monitor_probe;
insert into public.monitor_probe values (3);
set role pg_read_all_data;
select count(*) from public.monitor_probe;
reset session authorization;
drop table public.monitor_probe;

-- it can switch off pg_stat_statements tracking and cap temp files for its
-- own session
set session authorization supabase_monitor_admin;
set pg_stat_statements.track = none;
set temp_file_limit = '15MB';
show pg_stat_statements.track;
show temp_file_limit;
reset session authorization;
reset pg_stat_statements.track;
reset temp_file_limit;

-- it sees read-only mode as set by manage_readonly_mode.sh through
-- pg_file_settings, even though its own sessions default to read-only
alter system set default_transaction_read_only = on;
set session authorization supabase_monitor_admin;
select setting, applied from pg_file_settings where name = 'default_transaction_read_only';
reset session authorization;
alter system reset default_transaction_read_only;
set session authorization supabase_monitor_admin;
select count(*) from pg_file_settings where name = 'default_transaction_read_only';
-- but it cannot read pg_hba.conf / pg_ident.conf
select count(*) from pg_hba_file_rules;
select count(*) from pg_ident_file_mappings;
reset session authorization;

-- reserved role (supautils.conf.j2): the non-superuser postgres role cannot
-- grant it, modify it, grant to it, or drop it. Same pattern as
-- supautils_reserved_roles.sql.
begin;
set role postgres;
savepoint s;
grant supabase_monitor_admin to postgres;
rollback to savepoint s;
alter role supabase_monitor_admin password 'x';
rollback to savepoint s;
alter role supabase_monitor_admin set search_path = public;
rollback to savepoint s;
grant authenticated to supabase_monitor_admin;
rollback to savepoint s;
drop role supabase_monitor_admin;
rollback to savepoint s;
reset role;
rollback;
