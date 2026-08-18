-- amcheck is installable by customers (PSQL-1327): it lives in
-- supautils.privileged_extensions, so the non-superuser `postgres` role can
-- `create extension amcheck` and call bt_index_check() to find corrupt indexes
-- without a full REINDEX DATABASE.
--
-- The schema it lands in is `extensions`. amcheck deliberately
-- performs no permission check of its own -- upstream verify_nbtree.c says
-- "Intentionally not checking permissions" -- so its `REVOKE ALL ... FROM
-- PUBLIC` is the only access control, and any role holding EXECUTE can check
-- any index in the database.
--
-- Two standing ALTER DEFAULT PRIVILEGES rules decide which role gets that EXECUTE,
-- because supautils creates privileged extensions as supabase_admin:
--
--   * schema public     -> postgres, anon, authenticated, service_role
--     (migrations/db/init-scripts/00000000000000-initial-schema.sql)
--   * schema extensions -> postgres only
--     (migrations/db/migrations/20230224042246_grant_extensions_perms_for_postgres.sql)
--
-- Landing in public would therefore expose bt_index_parent_check() (ShareLock,
-- blocks writes) and verify_heapam() to unauthenticated PostgREST callers. So
-- supautils.extensions_parameter_overrides pins amcheck to `extensions`, and
-- this suite asserts both the placement and the resulting privilege matrix.
--
-- Runs against the rendered supautils.conf.j2 with the real migrations applied,
-- so the roles below are the actual platform roles.

-- the platform config pins amcheck's schema
show supautils.extensions_parameter_overrides;

-- precondition: postgres is not a superuser, else every assertion is vacuous
select rolsuper from pg_roles where rolname = 'postgres';

-- prime.sql already created amcheck; drop it so the creates below are observable
drop extension if exists amcheck;

-- a non-superuser can install it, and it lands in `extensions` rather than the
-- session search_path's first entry (public)
set role postgres;
create extension amcheck;
reset role;

select extowner::regrole as owner, extnamespace::regnamespace as schema
  from pg_extension
 where extname = 'amcheck';

-- the override wins over an explicitly requested schema, so the placement
-- cannot be opted out of
drop extension amcheck;

set role postgres;
create extension amcheck with schema public;
reset role;

select extnamespace::regnamespace as schema_after_requesting_public
  from pg_extension
 where extname = 'amcheck';

-- the privilege matrix that placement produces. Aggregated over every function
-- the extension owns rather than named signatures, so this stays correct as
-- amcheck gains functions across PG versions (15 ships 6, 17 ships 8) and
-- catches any future addition that arrives with different grants.
select r.rolname,
       bool_and(has_function_privilege(r.rolname, p.oid, 'execute')) as all_functions,
       bool_or(has_function_privilege(r.rolname, p.oid, 'execute')) as any_function
  from pg_proc p
  join pg_depend d on d.objid = p.oid and d.deptype = 'e'
  join pg_extension e on e.oid = d.refobjid and e.extname = 'amcheck'
 cross join (values ('postgres'), ('anon'), ('authenticated'), ('service_role')) as r(rolname)
 group by r.rolname
 order by r.rolname;

-- the support use case: postgres checks its own index, and -- since amcheck has
-- no per-relation gate -- one on a table it does not own, which is what makes
-- the extension useful after a 15->17 upgrade corrupts an auth index
set role postgres;
create table amcheck_heap(i int primary key) using heap;
insert into amcheck_heap select generate_series(1, 100);
select extensions.bt_index_check('amcheck_heap_pkey'::regclass);
select extensions.bt_index_check('auth.users_pkey'::regclass);
reset role;

-- the API roles must not reach it. The denial is at the function level, so it
-- applies to every target relation, not just this one.
set role anon;
select extensions.bt_index_check('auth.users_pkey'::regclass);
reset role;

-- restore the state prime.sql created (amcheck present, in `extensions`)
set role postgres;
drop table amcheck_heap;
reset role;
