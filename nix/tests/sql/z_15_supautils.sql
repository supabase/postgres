begin;
  load 'supautils';

  -- verify that supautils configuration parameters exist
  select current_setting('supautils.privileged_extensions', true) is not null as has_privileged_extensions;
  select current_setting('supautils.privileged_role', true) is not null as has_privileged_role;

  -- switch to postgres role and verify access to settings
  set role postgres;
  select current_setting('supautils.privileged_extensions', true) as privileged_extensions;

  -- create a simple schema to verify normal operations work
  create schema v;

  create table v.test_table (
    id serial primary key,
    data text
  );

  insert into v.test_table (data)
  values ('test1'), ('test2');

  select * from v.test_table order by id;

rollback;
