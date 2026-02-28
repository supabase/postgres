-- migrate:up
do $$
begin
    if exists (select 1 from pg_extension where extname = 'orioledb') then
        grant execute on function extensions.orioledb_rewind_by_time(int) to postgres;
        grant execute on function extensions.orioledb_rewind_to_transaction(int, bigint) to postgres;
        grant execute on function extensions.orioledb_rewind_to_timestamp(timestamptz) to postgres;
    end if;
end $$;

-- migrate:down
