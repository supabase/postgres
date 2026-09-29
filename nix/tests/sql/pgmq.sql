-- Test the standard flow
select
  pgmq.create('Foo');

select
  *
from
  pgmq.send(
    queue_name:='Foo',
    msg:='{"foo": "bar1"}'
  );

-- Test queue is not case sensitive
select
  *
from
  pgmq.send(
    queue_name:='foo', -- note: lowercase useage
    msg:='{"foo": "bar2"}',
    delay:=5
  );

select
  msg_id,
  read_ct,
  message
from
  pgmq.read(
    queue_name:='Foo',
    vt:=30,
    qty:=2
  );

select
  msg_id,
  read_ct,
  message
from
  pgmq.pop('Foo');


-- Archive message with msg_id=2.
select
  pgmq.archive(
    queue_name:='Foo',
    msg_id:=2
  );


select
  pgmq.create('my_queue');

select
  pgmq.send_batch(
  queue_name:='my_queue',
  msgs:=array['{"foo": "bar3"}','{"foo": "bar4"}','{"foo": "bar5"}']::jsonb[]
);

select
  pgmq.archive(
    queue_name:='my_queue',
    msg_ids:=array[3, 4, 5]
  );

select
  pgmq.delete('my_queue', 6);


select
  pgmq.drop_queue('my_queue');

/*
-- Disabled until pg_partman goes back into the image
select
  pgmq.create_partitioned(
    'my_partitioned_queue',
    '5 seconds',
    '10 seconds'
);
*/


-- Make sure SQLI enabling characters are blocked
select pgmq.create('F--oo');
select pgmq.create('F$oo');
select pgmq.create($$F'oo$$);
\echo

-- pgmq schema functions with owners (ownership is modified on ansible/files/postgresql_extension_custom_scripts/pgmq/after-create.sql)
select
  n.nspname as schema_name,
  p.proname as function_name,
  r.rolname as owner
from
  pg_proc p
join
  pg_namespace n on p.pronamespace = n.oid
join
  pg_roles r on p.proowner = r.oid
where
  n.nspname = 'pgmq'
order by
  p.proname;

-- assert search_path is preserved after after-create script is run
show search_path;

-- pgmq/after-create.sql runs as superuser and reassigns ownership of every
-- object depending on the pgmq extension's oid to postgres. The oid is looked
-- up in pg_extension, which must not be shadowable by a temp table. Point the
-- shadow at pg_tle's pg_tle_features type to try to hijack pg_tle's objects.
drop extension pgmq cascade;

create temp table pg_extension (oid oid, extname text, extversion text, extowner oid);
insert into pg_extension
  values ('pgtle.pg_tle_features'::regtype::oid, 'pgmq', '1.5.1', 'postgres'::regrole);

create extension pgmq;

drop table pg_temp.pg_extension;

-- pg_tle's objects must still be owned by supabase_admin
select 'pgtle.feature_info'::regclass::text as obj, relowner::regrole as owner
from pg_class
where oid = 'pgtle.feature_info'::regclass
union all
select p.oid::regprocedure::text, p.proowner::regrole
from pg_proc p
where p.oid = 'pgtle.register_feature(regproc,pgtle.pg_tle_features)'::regprocedure;

-- pgmq's own objects must have been reassigned to postgres
select count(*) as pgmq_functions_not_owned_by_postgres
from pg_proc p
where p.pronamespace = 'pgmq'::regnamespace and p.proowner != 'postgres'::regrole;

-- restore the 'Foo' queue dropped by the cascade above
select pgmq.create('Foo');
