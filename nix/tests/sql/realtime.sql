-- only a publication from supabase realtime is expected
SELECT
    pubname AS publication_name,
    pubowner::regrole AS owner,
    puballtables,
    pubinsert,
    pubupdate,
    pubdelete,
    pubtruncate
FROM
    pg_publication;

-- realtime schema owner
select
  n.nspname as schema_name,
  r.rolname as owner
from
  pg_namespace n
join
  pg_roles r on n.nspowner = r.oid
where
  n.nspname = 'realtime';

-- realtime schema acl
select
  n.nspname as schema_name,
  a.privilege_type,
  r.rolname as grantee,
  a.is_grantable
from
  pg_namespace n
cross join lateral
  aclexplode(n.nspacl) as a
join
  pg_roles r on a.grantee = r.oid
where
  n.nspname = 'realtime'
order by
  a.privilege_type, r.rolname;

-- supabase_realtime_admin role attributes
select
  rolname,
  rolsuper,
  rolinherit,
  rolcreaterole,
  rolcreatedb,
  rolcanlogin,
  rolreplication,
  rolbypassrls,
  rolconfig
from pg_roles
where rolname = 'supabase_realtime_admin';

-- postgres must not be a member of supabase_realtime_admin (SEC-562)
select
  r.rolname as role,
  m.rolname as member
from pg_auth_members am
join pg_roles r on r.oid = am.roleid
join pg_roles m on m.oid = am.member
where r.rolname = 'supabase_realtime_admin';

-- postgres must not have CREATE on realtime schema (SEC-562)
select
  has_schema_privilege('postgres', 'realtime', 'CREATE') as postgres_can_create,
  has_schema_privilege('postgres', 'realtime', 'USAGE')  as postgres_can_use;

-- postgres can grant realtime usage to custom roles
create role r;
grant r to postgres with admin option;

set role postgres;
grant usage on schema realtime to r;
select pg_catalog.has_schema_privilege('r', 'realtime', 'usage');

set role postgres;
drop owned by r cascade;
drop role r;
reset role;
