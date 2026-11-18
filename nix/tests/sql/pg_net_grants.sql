-- pg_net grants are made by postgres, not supabase_admin, so a customer can revoke anon,
-- authenticated and service_role themselves. extensions.apply_pg_net_grants() does that. It runs
-- from the migration and from the event trigger on CREATE and ALTER EXTENSION pg_net.
-- pg_net here was installed by prime.sql through the event trigger, the path a fresh project takes.

-- who holds what on the net schema and the http functions, and who granted it
create temp view net_acl as
select kind, name, privilege_type, grantee, grantor, is_grantable
from (
    select o.kind, o.name, a.privilege_type,
           case a.grantee when 0 then 'PUBLIC' else a.grantee::regrole::text end as grantee,
           a.grantor::regrole::text as grantor,
           a.is_grantable
    from (
        select 'schema' as kind, n.nspname::text as name, n.nspacl as acl
        from pg_namespace n
        where n.nspname = 'net'
        union all
        select 'function', p.proname::text, p.proacl
        from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'net'
          and p.proname in ('http_get', 'http_post', 'http_delete')
    ) o
    cross join lateral aclexplode(o.acl) a
) x
order by kind, name, grantee collate "C", privilege_type;

-- what each role can actually do, through its own grants or through PUBLIC
create temp view net_access as
select r.rolname,
       has_schema_privilege(r.rolname, 'net', 'USAGE') as schema_usage,
       bool_and(has_function_privilege(r.rolname, p.oid, 'EXECUTE')) as http_execute
from pg_roles r,
     pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
where r.rolname in ('postgres', 'anon', 'authenticated', 'service_role', 'supabase_functions_admin')
  and n.nspname = 'net'
  and p.proname in ('http_get', 'http_post', 'http_delete')
group by r.rolname
order by r.rolname collate "C";

-- 1. fresh project: anon, authenticated and service_role are granted by postgres, postgres can
--    grant onward, supabase_functions_admin keeps its grants from supabase_admin
select * from net_acl;
select * from net_access;

-- 2. running the routine again changes nothing
select extensions.apply_pg_net_grants();
select * from net_acl;

-- 3. existing project: the old event trigger granted the three roles as supabase_admin, and
--    support revoked anon by hand. authenticated and service_role keep their access, now granted
--    by postgres. anon gets nothing back
set role postgres;
revoke usage on schema net from anon, authenticated, service_role;
revoke execute on function net.http_get, net.http_post, net.http_delete from anon, authenticated, service_role;
reset role;
grant usage on schema net to anon, authenticated, service_role;
revoke usage on schema net from anon;
select extensions.apply_pg_net_grants();
select * from net_acl;

-- 4. the customer revokes authenticated. A later run does not bring it back
set role postgres;
revoke usage on schema net from authenticated;
revoke execute on function net.http_get, net.http_post, net.http_delete from authenticated;
reset role;
select extensions.apply_pg_net_grants();
select * from net_acl;

-- 5. upgraded project: the upgrade scripts make http_get and http_post SECURITY DEFINER,
--    revoke PUBLIC on them and grant the five roles as supabase_admin. The grants move to
--    postgres, function security is left alone
drop extension pg_net;
create extension pg_net;
set role postgres;
revoke usage on schema net from anon, authenticated, service_role;
revoke execute on function net.http_get, net.http_post, net.http_delete from anon, authenticated, service_role;
reset role;
alter function net.http_get security definer;
alter function net.http_post security definer;
revoke all on function net.http_get, net.http_post from public;
grant usage on schema net to supabase_functions_admin, postgres, anon, authenticated, service_role;
grant execute on function net.http_get, net.http_post to supabase_functions_admin, postgres, anon, authenticated, service_role;
select extensions.apply_pg_net_grants();
select * from net_acl;
select * from net_access;
select p.proname, p.prosecdef
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'net'
  and p.proname in ('http_get', 'http_post', 'http_delete')
order by p.proname;

-- 6. drop and recreate the extension as postgres, the way a project does it. supautils runs the
--    trigger in a security-restricted context, and the three roles still get the set from postgres.
set role postgres;
drop extension pg_net;
create extension pg_net;
reset role;
select * from net_acl;

-- 6.1 a helper the customer replaced is not what runs: the routine drops and recreates it
set role postgres;
create or replace function extensions.grant_pg_net_api_access(api_role name, http_functions regprocedure[])
    returns void language plpgsql as $$ begin raise exception 'customer body ran as %', current_user; end $$;
reset role;
select extensions.apply_pg_net_grants();
select prosecdef, proowner::regrole as owner
  from pg_proc where oid = 'extensions.grant_pg_net_api_access(name, regprocedure[])'::regprocedure;

-- 7. anon can queue a request with its grants from postgres. Then wait for the worker to finish
--    it, so it cannot fire a trigger that a later test plants on the response table
select value as port from test_config where key = 'http_mock_port' \gset
set role anon;
select net.http_get('http://localhost:' || :'port' || '/get') as request_id \gset
reset role;
select set_config('pg_net_grants.request_id', :'request_id', false) is not null as request_queued;
do $$
begin
    for i in 1..40 loop
        exit when exists (select from net._http_response where id = current_setting('pg_net_grants.request_id')::bigint);
        perform pg_sleep(0.25);
    end loop;
end;
$$;

-- 8. PUBLIC loses TRIGGER, REFERENCES and TRUNCATE on the tables, postgres gets TRIGGER and TRUNCATE.
--    The rest of what pg_net grants PUBLIC is still there
select relname, grantee, string_agg(privilege_type, ', ' order by privilege_type) as privileges
from (
    select c.relname,
           case a.grantee when 0 then 'PUBLIC' else a.grantee::regrole::text end as grantee,
           a.privilege_type
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    cross join lateral aclexplode(c.relacl) a
    where n.nspname = 'net'
      and c.relkind in ('r', 'S')
      and a.privilege_type <> 'MAINTAIN' -- PG17+
) x
group by relname, grantee
order by relname, grantee collate "C";

-- 9. postgres is still a superuser, as it is during an upgrade until complete.sh demotes it. The
--    routine warns and changes nothing: a grant made now would be recorded as made by supabase_admin
alter role postgres superuser;
select extensions.apply_pg_net_grants();
alter role postgres nosuperuser;
select * from net_acl;
