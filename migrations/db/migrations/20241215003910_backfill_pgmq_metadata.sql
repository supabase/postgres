-- migrate:up
do $$
begin
    -- Check if the pgmq.meta table exists
    if exists (
        select
            1
        from
            pg_catalog.pg_class c
        join pg_catalog.pg_namespace n
            on c.relnamespace = n.oid
        where
            n.nspname = 'pgmq'
            and c.relname = 'meta'
            and c.relkind = 'r' -- regular table
            -- Make sure only expected columns exist and are correctly named
            and (
                select array_agg(attname::text order by attname)
                from pg_catalog.pg_attribute a
                where
                a.attnum > 0
                and a.attrelid = c.oid 
            ) = array['created_at', 'is_partitioned', 'is_unlogged', 'queue_name']::text[]
    ) then
        -- Insert data into pgmq.meta for all tables matching the naming pattern 'pgmq.q_<queue_name>'
        insert into pgmq.meta (queue_name, is_partitioned, is_unlogged, created_at)
        select
            substring(c.relname from 3) as queue_name,
            false as is_partitioned,
            case when c.relpersistence = 'u' then true else false end as is_unlogged,
            now() as created_at
        from
			pg_catalog.pg_class c
        	join pg_catalog.pg_namespace n
				on c.relnamespace = n.oid
        where
            n.nspname = 'pgmq'
            and c.relname like 'q_%'
            and c.relkind in ('r', 'p', 'u')
        on conflict (queue_name) do nothing;
    end if;
end $$;

-- migrate:down
