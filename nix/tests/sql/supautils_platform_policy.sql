-- Reference example for platform-policy tests (see nix/tests/README.md).
--
-- This suite runs against the rendered supautils.conf.j2 with the real
-- migrations applied, so supautils behavior can be asserted as the actual
-- platform roles. The session user (supabase_admin) is the cluster
-- superuser, so policy tests must SET ROLE to the role the policy targets.

-- the platform supautils config is loaded
show supautils.privileged_role;

-- postgres is not a superuser: supautils policies apply to it
select rolsuper from pg_roles where rolname = 'postgres';

-- privileged extension creation is delegated to the configured superuser
-- for non-superusers (supautils.privileged_extensions +
-- supautils.privileged_extensions_superuser)
drop extension hstore;

set role postgres;
create extension hstore;
select count(*) = 1 as installed from pg_extension where extname = 'hstore';
reset role;

-- the delegated create leaves the extension owned by the configured
-- superuser, same as the primed state
select rolname from pg_roles r
  join pg_extension e on e.extowner = r.oid
 where e.extname = 'hstore';
