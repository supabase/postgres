set client_min_messages = warning;

-- before-create.sql runs as superuser and pre-creates the privileged
-- dependencies of a TLE created with cascade. It must not pre-create
-- dependencies which are themselves TLEs, because TLE code is controlled by
-- a non-superuser. pljava is in supautils.privileged_extensions but has no
-- control file on disk, so a non-superuser can claim the name as a TLE.
create role tle_privesc_test_role;

set role postgres;

select
  pgtle.install_extension(
    'pljava',
    '1.0',
    'Tries to make tle_privesc_test_role a superuser',
    $_pg_tle_$
      alter role tle_privesc_test_role with superuser;
    $_pg_tle_$
  );

select
  pgtle.install_extension(
    'tle_privesc_test_dependent',
    '1.0',
    'Depends on the pljava TLE',
    $_pg_tle_$
      select 1;
    $_pg_tle_$,
    array['pljava']
  );

-- the pljava TLE is created as postgres, so the alter role fails with
-- insufficient_privilege (the error message differs between PG versions)
\set VERBOSITY sqlstate
create extension tle_privesc_test_dependent cascade;

-- shadowing pg_available_extensions with a temp table must not trick
-- before-create.sql into treating the pljava TLE as an on-disk extension
create temp table pg_available_extensions (name name, default_version text);
insert into pg_available_extensions values ('pljava', '1.0');

create extension tle_privesc_test_dependent cascade;
\set VERBOSITY default

drop table pg_temp.pg_available_extensions;

reset role;

select rolname, rolsuper from pg_roles where rolname = 'tle_privesc_test_role';

select extname from pg_extension where extname in ('pljava', 'tle_privesc_test_dependent');

-- non-TLE privileged dependencies reached transitively through TLEs
-- (TLE -> TLE -> non-TLE) must still be pre-created as superuser, in the
-- schema they would be created in without before-create.sql
set role postgres;

select
  pgtle.install_extension(
    'tle_transitive_test_leaf',
    '1.0',
    'Depends on tsm_system_time',
    $_pg_tle_$
      select 1;
    $_pg_tle_$,
    array['tsm_system_time']
  );

select
  pgtle.install_extension(
    'tle_transitive_test_root',
    '1.0',
    'Depends on the tle_transitive_test_leaf TLE',
    $_pg_tle_$
      select 1;
    $_pg_tle_$,
    array['tle_transitive_test_leaf']
  );

create extension tle_transitive_test_root cascade;

-- assert search_path is preserved after before-create script is run
show search_path;

reset role;

select extname, extowner::regrole as owner, extnamespace::regnamespace as schema
from pg_extension
where extname in ('tsm_system_time', 'tle_transitive_test_leaf', 'tle_transitive_test_root')
order by extname;

drop extension tle_transitive_test_root, tle_transitive_test_leaf, tsm_system_time;

select pgtle.uninstall_extension('tle_transitive_test_root');
select pgtle.uninstall_extension('tle_transitive_test_leaf');
select pgtle.uninstall_extension('tle_privesc_test_dependent');
select pgtle.uninstall_extension('pljava');

drop role tle_privesc_test_role;
