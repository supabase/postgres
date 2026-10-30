-- migrate:up

-- pgmq/after-create.sql replaces pgmq.drop_queue with an override (and a
-- 2-arg compat shim) that previously resolved names through the caller's
-- search_path. New installs now pin it; pin it on existing instances too.
-- Every drop_queue body shipped by pgmq (1.4.4, 1.5.1) or by the override
-- schema-qualifies its non-catalog references, so pinning is safe whichever
-- one an instance currently has.
do $$
begin
  if to_regprocedure('pgmq.drop_queue(text)') is not null then
    alter function pgmq.drop_queue(text) set search_path = pg_catalog, pg_temp;
  end if;
  if to_regprocedure('pgmq.drop_queue(text, boolean)') is not null then
    alter function pgmq.drop_queue(text, boolean) set search_path = pg_catalog, pg_temp;
  end if;
end $$;

-- migrate:down
