-- supabase_monitor_admin: passwordless, read-only monitoring role
-- (migrations/db/migrations/20261113000000_supabase_monitor_admin.sql)

-- attributes: login, no password, bypassrls, no connection limit, nothing else
select rolsuper, rolinherit, rolcreaterole, rolcreatedb, rolcanlogin,
       rolreplication, rolbypassrls, rolconnlimit, rolpassword is null as no_password
from pg_authid where rolname = 'supabase_monitor_admin';

-- per-role settings (read-only by default, search_path pg_catalog + pg_temp, timeouts)
select unnest(rolconfig) as setting from pg_roles where rolname = 'supabase_monitor_admin' order by 1;

-- memberships: exactly pg_monitor and pg_read_all_data
select roleid::regrole::text as role, admin_option
from pg_auth_members where member = 'supabase_monitor_admin'::regrole order by 1;

-- nobody is a member of it
select count(*) from pg_auth_members where roleid = 'supabase_monitor_admin'::regrole;

-- owns nothing and holds no object-level ACL entries anywhere
select count(*) from pg_shdepend
where refclassid = 'pg_authid'::regclass
  and refobjid = 'supabase_monitor_admin'::regrole
  and deptype in ('o', 'a');

-- no CREATE on the database
select has_database_privilege('supabase_monitor_admin', current_database(), 'CREATE');

-- reads every table regardless of RLS, but cannot write; SET ROLE to a
-- predefined role only loses privileges (BYPASSRLS stays with
-- supabase_monitor_admin)
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
