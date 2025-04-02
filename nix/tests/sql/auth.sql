-- auth schema owner
select
  n.nspname as schema_name,
  r.rolname as owner
from
  pg_namespace n
join
  pg_roles r on n.nspowner = r.oid
where
  n.nspname = 'auth';

-- attributes of the supabase_auth_admin
select
  rolcreaterole  ,
  rolcanlogin    ,
  rolsuper       ,
  rolinherit     ,
  rolcreatedb    ,
  rolreplication ,
  rolconnlimit   ,
  rolbypassrls   ,
  rolvaliduntil
from pg_roles r
where r.rolname = 'supabase_auth_admin';

select
  rolconfig
from pg_roles r
where r.rolname = 'supabase_auth_admin';

-- auth schema tables with owners
select
  n.nspname as schema_name,
  c.relname as table_name,
  r.rolname as owner
from
  pg_class c
join
  pg_namespace n on c.relnamespace = n.oid
join
  pg_roles r on c.relowner = r.oid
where
  c.relkind in ('r')  -- 'r' for regular tables
  and n.nspname = 'auth'
order by
  c.relname;

-- auth indexes with owners
select
  ns.nspname as table_schema,
  t.relname as table_name,
  i.relname as index_name,
  r.rolname as index_owner
from
  pg_class t
join
  pg_namespace ns on t.relnamespace = ns.oid
join
  pg_index idx on t.oid = idx.indrelid
join
  pg_class i on idx.indexrelid = i.oid
join
  pg_roles r on i.relowner = r.oid
where
  ns.nspname = 'auth'
order by
  t.relname, i.relname;

-- auth schema functions with owners
select
  n.nspname as schema_name,
  p.proname as function_name,
  r.rolname as owner
from
  pg_proc p
join
  pg_namespace n on p.pronamespace = n.oid
join
  pg_roles r on p.proowner = r.oid
where
  n.nspname = 'auth'
order by
  p.proname;

-- roles which have USAGE on the auth schema
select
  n.nspname as schema_name,
  r.rolname as role_name,
  a.privilege_type
from
  pg_namespace n
cross join lateral aclexplode(n.nspacl) as a
join
  pg_roles r on a.grantee = r.oid
where
  n.nspname = 'auth'
  and a.privilege_type = 'USAGE'
order by
  r.rolname;

-- roles which have CREATE on the auth schema
select
  n.nspname as schema_name,
  r.rolname as role_name,
  a.privilege_type
from
  pg_namespace n
cross join lateral aclexplode(n.nspacl) as a
join
  pg_roles r on a.grantee = r.oid
where
  n.nspname = 'auth'
  and a.privilege_type = 'CREATE'
order by
  r.rolname;
