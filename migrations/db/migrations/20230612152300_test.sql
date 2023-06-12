-- migrate:up

create or replace function auth.test() returns void language plpgsql as $$
begin
  return;
end;
$$;

-- migrate:down

