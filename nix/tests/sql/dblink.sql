-- dblink/after-create.sql runs as superuser and revokes execute on
-- dblink_connect_u from everyone except supabase_admin. dblink_connect_u lets
-- the caller connect as any role without a password, so a leftover grant is a
-- path to superuser. The functions are looked up in pg_proc, which must not
-- be shadowable by a temp table.
drop extension dblink cascade;

set role postgres;

create temp table pg_proc (oid oid, proname text, proacl aclitem[]);

create extension dblink;

drop table pg_temp.pg_proc;

reset role;

-- only supabase_admin may execute dblink_connect_u
select p.oid::regprocedure as function_name, acl.grantee::regrole as grantee, acl.privilege_type
from pg_proc p
cross join lateral aclexplode(p.proacl) as acl
where p.proname = 'dblink_connect_u'
order by 1, 2;

select
  has_function_privilege('postgres', 'dblink_connect_u(text)', 'execute') as connect_u_1,
  has_function_privilege('postgres', 'dblink_connect_u(text,text)', 'execute') as connect_u_2;

-- assert search_path is preserved after after-create script is run
show search_path;

-- recreate dblink as it was created by prime.sql
drop extension dblink;

create extension dblink;
