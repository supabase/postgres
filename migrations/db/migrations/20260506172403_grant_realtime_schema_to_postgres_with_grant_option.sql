-- migrate:up

do $$
begin
  if exists (select from pg_namespace where nspname = 'realtime') then
    grant usage on schema realtime to postgres with grant option;
  end if;
end $$;

-- migrate:down
