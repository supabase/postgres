set client_min_messages = warning;

-- The following test verifies that creating a pg_available_extensions in
-- pg_temp doesn't trick global before-create.sql into treating the non-TLE
-- extensions in supautils.privileged_extensions as TLE extensions and allowing
-- privilege escalation.
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

-- The pljava TLE is created as postgres, so the alter role fails with
-- insufficient_privilege. Since the error message differs between PG versions
-- we set the verbosity so that only error code is printed, which is the same
-- between versions.
\set VERBOSITY sqlstate
create extension tle_privesc_test_dependent cascade;

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
