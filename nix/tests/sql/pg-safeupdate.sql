load 'safeupdate';

set safeupdate.enabled=1;

create schema v;

create table v.foo(
  id int,
  val text
);

update v.foo
  set val = 'bar';

grant all on schema v to authenticated;
set role authenticated;

delete from v.foo;
reset role;
drop schema v cascade;



