-- Tests role privileges on the vault objects
-- INSERT and UPDATE privileges should not be present on the vault tables for postgres and service_role, only SELECT and DELETE
WITH schema_obj AS (
  SELECT oid, nspname
  FROM pg_namespace
  WHERE nspname = 'vault'
)
SELECT
  s.nspname AS schema,
  c.relname AS object_name,
  acl.grantee::regrole::text AS grantee,
  acl.privilege_type
FROM pg_class c
JOIN schema_obj s ON s.oid = c.relnamespace
CROSS JOIN LATERAL aclexplode(c.relacl) AS acl
WHERE c.relkind IN ('r', 'v', 'm', 'f', 'p')
  AND acl.privilege_type <> 'MAINTAIN'
UNION ALL
SELECT
  s.nspname AS schema,
  p.proname AS object_name,
  acl.grantee::regrole::text AS grantee,
  acl.privilege_type
FROM pg_proc p
JOIN schema_obj s ON s.oid = p.pronamespace
CROSS JOIN LATERAL aclexplode(p.proacl) AS acl
ORDER BY object_name, grantee, privilege_type;

-- vault indexes with owners
SELECT
    ns.nspname AS schema,
    t.relname AS table,
    i.relname AS index_name,
    r.rolname AS index_owner,
    CASE
        WHEN idx.indisunique THEN 'Unique'
        ELSE 'Non Unique'
    END AS index_type
FROM
    pg_class t
JOIN
    pg_namespace ns ON t.relnamespace = ns.oid
JOIN
    pg_index idx ON t.oid = idx.indrelid
JOIN
    pg_class i ON idx.indexrelid = i.oid
JOIN
    pg_roles r ON i.relowner = r.oid
WHERE
    ns.nspname = 'vault'
ORDER BY
    t.relname,
    i.relname;

-- assert search_path is preserved after after-create script is run
show search_path;

-- supabase_vault/after-create.sql runs as superuser and grants postgres and
-- service_role access to vault unless the extension version is 0.2.8. The
-- version is looked up in pg_extension, which must not be shadowable by a
-- temp table.
set client_min_messages = warning;

drop extension supabase_vault cascade;

create temp table pg_extension (oid oid, extname text, extversion text, extowner oid);
insert into pg_extension values (0, 'supabase_vault', '0.2.8', 'postgres'::regrole);

create extension supabase_vault;

drop table pg_temp.pg_extension;

reset client_min_messages;

-- postgres and service_role must have been granted access
select p.proname as function_name, acl.grantee::regrole::text as grantee, acl.privilege_type
from pg_proc p
cross join lateral aclexplode(p.proacl) as acl
where p.pronamespace = 'vault'::regnamespace
  and acl.grantee::regrole::text in ('postgres', 'service_role')
order by 1, 2, 3;

select
  has_schema_privilege('postgres', 'vault', 'usage') as postgres_usage,
  has_schema_privilege('service_role', 'vault', 'usage') as service_role_usage;

-- assert search_path is preserved after after-create script is run
show search_path;
