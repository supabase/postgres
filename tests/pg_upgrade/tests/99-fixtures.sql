-- enable JIT to ensure the upgrade process disables it
alter system set jit = on;
alter system set password_encryption = 'md5';
select pg_reload_conf();

-- create materialized view
create materialized view public.european_countries as
    select * from public.countries where continent = 'Europe'
with no data;
refresh materialized view public.european_countries;

select count(*) from public.european_countries;

-- simulate a project created before the trigger rescope migrations: the
-- fleet-wide function updates left these projects with triggers still scoped
-- to their original tags, so recreating the extensions no longer re-applies
-- their wiring (graphql_public.graphql wrapper, cron grants). The upgrade
-- must rescope both to CREATE EXTENSION.
drop event trigger if exists issue_pg_graphql_access;
create event trigger issue_pg_graphql_access
    on ddl_command_end
    when tag in ('CREATE FUNCTION')
    execute procedure extensions.grant_pg_graphql_access();
drop event trigger if exists issue_pg_cron_access;
create event trigger issue_pg_cron_access
    on ddl_command_end
    when tag in ('CREATE SCHEMA')
    execute procedure extensions.grant_pg_cron_access();

-- simulate a running project that never received the pg_net grants migration: no routine, the
-- event trigger only on CREATE EXTENSION, no grants from postgres, and the old upgrade script
-- granted pg_net to anon, authenticated and service_role as supabase_admin, then support revoked
-- anon by hand. PUBLIC still has everything pg_net grants on the tables. The upgrade must ship
-- the routine, hand the grants of authenticated and service_role to postgres, leave anon without
-- one and take TRIGGER away from PUBLIC.
drop function extensions.apply_pg_net_grants();
drop function extensions.grant_pg_net_api_access(name, regprocedure[]);
drop event trigger issue_pg_net_access;
create event trigger issue_pg_net_access
    on ddl_command_end
    when tag in ('CREATE EXTENSION')
    execute procedure extensions.grant_pg_net_access();
set role postgres;
revoke usage on schema net from anon, authenticated, service_role;
revoke execute on function net.http_get, net.http_post, net.http_delete from anon, authenticated, service_role;
reset role;
revoke trigger, truncate on all tables in schema net from postgres;
grant trigger, references, truncate on all tables in schema net to public;
grant usage on schema net to anon, authenticated, service_role;
grant execute on function net.http_get, net.http_post to anon, authenticated, service_role;
revoke usage on schema net from anon;
revoke execute on function net.http_get, net.http_post from anon;
