-- The following test verifies that creating pg_proc in pg_temp doesn't shadow
-- the real catalog table tricking the dblink/after-create.sql script to skip
-- revoking the grants from all roles except supabase_admin, which would have
-- lead to a privilege escalation attack since dblink_connect_u lets the caller
-- connect as any role without a password.
set client_min_messages = warning;

drop extension if exists dblink cascade;

set role postgres;

create temp table pg_proc (oid oid, proname text, proacl aclitem[]);

create extension dblink;

drop table pg_temp.pg_proc;

reset role;

select p.oid::regprocedure as function_name, acl.grantee::regrole as grantee, acl.privilege_type
from pg_proc p
cross join lateral aclexplode(p.proacl) as acl
where p.proname = 'dblink_connect_u'
order by 1, 2;

select
  has_function_privilege('postgres', 'dblink_connect_u(text)', 'execute') as connect_u_1,
  has_function_privilege('postgres', 'dblink_connect_u(text,text)', 'execute') as connect_u_2;

show search_path;

drop extension dblink;

create extension dblink;
