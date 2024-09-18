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
  msg_id,
  read_ct,
  message
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

select
  pgmq.create_partitioned('my_partitioned_queue');


-- Make sure SQLI enabling characters are blocked
select pgmq.create('F--oo');
select pgmq.create('F$oo');
select pgmq.create($$F'oo$$);




