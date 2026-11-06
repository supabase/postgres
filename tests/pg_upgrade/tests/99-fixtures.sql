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

-- simulate a running project that never received the pg_net grants migration: no routine, and
-- the old upgrade script granted pg_net to anon, authenticated and service_role as supabase_admin,
-- then support revoked anon by hand. The upgrade must ship the routine, hand the grants of
-- authenticated and service_role to postgres and leave anon without one.
drop function extensions.apply_pg_net_grants();
grant usage on schema net to anon, authenticated, service_role;
grant execute on function net.http_get, net.http_post to anon, authenticated, service_role;
revoke usage on schema net from anon;
revoke execute on function net.http_get, net.http_post from anon;
