set client_min_messages = warning;

select
  pgtle.install_extension(
    'pg_distance',
    '0.1',
    'Distance functions for two points',
    $_pg_tle_$
      CREATE FUNCTION dist(x1 float8, y1 float8, x2 float8, y2 float8, norm int)
      RETURNS float8
      AS $$
        SELECT (abs(x2 - x1) ^ norm + abs(y2 - y1) ^ norm) ^ (1::float8 / norm);
      $$ LANGUAGE SQL;

      CREATE FUNCTION manhattan_dist(x1 float8, y1 float8, x2 float8, y2 float8)
      RETURNS float8
      AS $$
        SELECT dist(x1, y1, x2, y2, 1);
      $$ LANGUAGE SQL;

      CREATE FUNCTION euclidean_dist(x1 float8, y1 float8, x2 float8, y2 float8)
      RETURNS float8
      AS $$
        SELECT dist(x1, y1, x2, y2, 2);
      $$ LANGUAGE SQL;
    $_pg_tle_$
  );

create extension pg_distance;

select manhattan_dist(1, 1, 5, 5)::numeric(10,2);
select euclidean_dist(1, 1, 5, 5)::numeric(10,2);

SELECT pgtle.install_update_path(
  'pg_distance',
  '0.1',
  '0.2',
  $_pg_tle_$
    CREATE OR REPLACE FUNCTION dist(x1 float8, y1 float8, x2 float8, y2 float8, norm int)
    RETURNS float8
    AS $$
      SELECT (abs(x2 - x1) ^ norm + abs(y2 - y1) ^ norm) ^ (1::float8 / norm);
    $$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

    CREATE OR REPLACE FUNCTION manhattan_dist(x1 float8, y1 float8, x2 float8, y2 float8)
    RETURNS float8
    AS $$
      SELECT dist(x1, y1, x2, y2, 1);
    $$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

    CREATE OR REPLACE FUNCTION euclidean_dist(x1 float8, y1 float8, x2 float8, y2 float8)
    RETURNS float8
    AS $$
      SELECT dist(x1, y1, x2, y2, 2);
    $$ LANGUAGE SQL IMMUTABLE PARALLEL SAFE;
  $_pg_tle_$
  );


select
  pgtle.set_default_version('pg_distance', '0.2');

alter extension pg_distance update;

drop extension pg_distance;

select
  pgtle.uninstall_extension('pg_distance');

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

-- Restore original state if any of the above fails
drop extension pg_tle cascade;

create extension pg_tle;
