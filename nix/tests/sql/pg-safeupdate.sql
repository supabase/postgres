load 'safeupdate';

set safeupdate.enabled=1;

create schema v;

create table v.foo(
  id int,
  val text
);

update v.foo
  set val = 'bar';

drop schema v cascade;

alter role postgres in database postgres set safeupdate.enabled = 1;

\c - postgres
create temp table t(id int);

update t set id = 1;

\c - supabase_admin
alter role postgres in database postgres reset safeupdate.enabled;
