-- Verify anon role has safeupdate in session_preload_libraries
select exists(
  select 1 from pg_db_role_setting s
  join pg_roles r on r.oid = s.setrole
  where r.rolname = 'anon'
  and s.setconfig @> array['session_preload_libraries=safeupdate']
) as anon_has_safeupdate;

-- Verify authenticated role has safeupdate in session_preload_libraries
select exists(
  select 1 from pg_db_role_setting s
  join pg_roles r on r.oid = s.setrole
  where r.rolname = 'authenticated'
  and s.setconfig @> array['session_preload_libraries=safeupdate']
) as authenticated_has_safeupdate;

load 'safeupdate';

set safeupdate.enabled=1;

create schema v;

create table v.foo(
  id int,
  val text
);

insert into v.foo values (1, 'test');

-- Should fail: UPDATE without WHERE
update v.foo
  set val = 'bar';

-- Should succeed: UPDATE with WHERE
update v.foo
  set val = 'bar'
  where id = 1;

set safeupdate.enabled=0;

-- Should succeed
delete from v.foo;

grant all on schema v to authenticated;
grant all on v.foo to authenticated;
grant all on schema v to postgres;
grant all on v.foo to postgres;
set role authenticated;

-- Should fail: DELETE without WHERE
delete from v.foo;

-- Should succeed: DELETE with WHERE
delete from v.foo
  where id = 1;

reset role;
drop schema v cascade;
