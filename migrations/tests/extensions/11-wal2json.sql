select pg_drop_replication_slot(slot_name) from pg_replication_slots where slot_name = 'test_slot';
select * from pg_create_logical_replication_slot('test_slot', 'wal2json');
