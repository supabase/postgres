-- migrate:up
do $$
begin
    -- Check if the pgmq.meta table exists
    if exists (
        select 1
        from pg_catalog.pg_class c
        join pg_catalog.pg_namespace n on c.relnamespace = n.oid
        where n.nspname = 'pgmq' and c.relname = 'meta'
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
	 		and c.relkind in ('r', 'p', 'u');
    end if;
end $$;

-- migrate:down
