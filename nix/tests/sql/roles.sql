-- all roles and attributes
select
  rolname,
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
-- TODO: this exclusion is to maintain compat with pg17, we should cover it
where rolname not in ('pg_create_subscription', 'pg_maintain', 'pg_use_reserved_connections')
order by rolname;

select
  rolname,
  rolconfig
from pg_roles r
-- TODO: this exclusion is to maintain compat with pg17, we should cover it
where rolname not in ('pg_create_subscription', 'pg_maintain', 'pg_use_reserved_connections')
order by rolname;

-- all role memberships
select
    r.rolname as member,
    g.rolname as "member_of (can become)",
    m.admin_option
from
    pg_roles r
left join
    pg_auth_members m on r.oid = m.member
left join
    pg_roles g on m.roleid = g.oid
-- TODO: this exclusion is to maintain compat with pg17, we should cover it
where r.rolname not in ('pg_create_subscription', 'pg_maintain', 'pg_use_reserved_connections')
order by
    r.rolname, g.rolname;

-- Check all privileges of the roles on the schemas
select schema_name, privilege_type, grantee, default_for
from (
    -- ALTER DEFAULT privileges on schemas
    select
        n.nspname as schema_name,
        a.privilege_type,
        r.rolname as grantee,
        d.defaclrole::regrole as default_for,
        case when n.nspname = 'public' then 0 else 1 end as schema_order
    from
        pg_default_acl d
    join
        pg_namespace n on d.defaclnamespace = n.oid
    cross join lateral aclexplode(d.defaclacl) as a
    join
        pg_roles r on a.grantee = r.oid
    where
        a.privilege_type != 'MAINTAIN' -- TODO: this is to maintain compat with pg17, we should cover it
    union all
    -- explicit grant usage and create on the schemas
    select
        n.nspname as schema_name,
        a.privilege_type,
        r.rolname as grantee,
        n.nspowner::regrole as default_for,
        case when n.nspname = 'public' then 0 else 1 end as schema_order
    from
        pg_namespace n
    cross join lateral aclexplode(n.nspacl) as a
    join
        pg_roles r on a.grantee = r.oid
    where
        a.privilege_type in ('CREATE', 'USAGE')
) sub
order by schema_order, schema_name, privilege_type, grantee, default_for;
