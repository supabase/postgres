-- migrate:up
drop extension if exists pg_graphql;

-- migrate:down
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_graphql') then
    create extension if not exists pg_graphql;
  end if;
end $$;
