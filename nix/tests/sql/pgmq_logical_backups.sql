/*
    This test confirms that the pgmq after-create supautils hook
    that replaces the drop_queue function is inter-operable with
    the infra hook that detaches pgmq queues from the pgmq
    extension's ownership prior to taking logical backups
*/

-- Create a queue
select pgmq.create('lb-test');

-- Add a record
select
  *
from
  pgmq.send(
    queue_name:='lb-test',
    msg:='{"foo": "bar1"}'
  );


/*
   COPY/PASTE of the on-pause hook that
   - detaches ownership of queues from the extension
   - updates identity columns to avoid pg_dump segfault
*/

do $$
declare
    tbl record;
    seq_name text;
    new_seq_name text;
    archive_table_name text;
begin
    -- Loop through each table in the pgmq schema starting with 'q_'
    -- Rebuild the pkey column's default to avoid pg_dumpall segfaults
    for tbl in
        select c.relname as table_name
        from pg_catalog.pg_attribute a
        join pg_catalog.pg_class c on c.oid = a.attrelid
        join pg_catalog.pg_namespace n on n.oid = c.relnamespace
        where n.nspname = 'pgmq'
            and c.relname like 'q_%'
            and a.attname = 'msg_id'
            and a.attidentity in ('a', 'd') -- 'a' for ALWAYS, 'd' for BY DEFAULT
    loop
        -- Check if msg_id is an IDENTITY column for idempotency
        -- Define sequence names
        seq_name := 'pgmq.' || format ('"%s_msg_id_seq"', tbl.table_name);
        new_seq_name := 'pgmq.' || format ('"%s_msg_id_seq2"', tbl.table_name);
        archive_table_name := regexp_replace(tbl.table_name, '^q_', 'a_');
        -- Execute dynamic SQL to perform the required operations
        execute format('
            create sequence %s;
            select setval(''%s'', nextval(''%s''));
            alter table %s."%s" alter column msg_id drop identity;
            alter table %s."%s" alter column msg_id set default nextval(''%s'');
            alter sequence %s rename to %s;
            alter sequence %s owner to postgres;',
            -- Parameters for format placeholders
            new_seq_name,
            new_seq_name, seq_name,
            'pgmq', tbl.table_name,
            'pgmq', tbl.table_name,
            new_seq_name,
            -- alter seq
            new_seq_name, format('"%s_msg_id_seq"', tbl.table_name),
            -- set owner
            seq_name
        );
    end loop;
    -- No tables should be owned by the extension.
    -- We want them to be included in logical backups
    for tbl in
        select c.relname as table_name
        from pg_class c
          join pg_depend d
            on c.oid = d.objid
          join pg_extension e
            on d.refobjid = e.oid
        where
          c.relkind in ('r', 'p', 'u')
          and e.extname = 'pgmq'
          and (c.relname like 'q_%' or c.relname like 'a_%')
    loop
      execute format('
        alter extension pgmq drop table pgmq."%s";',
        tbl.table_name
      );
    end loop;
end $$;

-- Now confirm that pgmq.drop_queue still works
select pgmq.drop_queue('lb-test');
