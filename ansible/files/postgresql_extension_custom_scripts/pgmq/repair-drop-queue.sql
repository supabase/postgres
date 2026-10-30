-- one-time repair: supautils only runs extension-custom-scripts on CREATE
-- EXTENSION, so installs that already ran it under the pre-#2539 hook never
-- pick up the new drop_queue(text, boolean) shim on their own.
do $$
begin
  if exists (select from pg_extension where extname = 'pgmq')
     and to_regprocedure('pgmq.drop_queue(text, boolean)') is null then
    create function pgmq.drop_queue(queue_name text, partitioned boolean)
    returns boolean language plpgsql as $f$
      begin return pgmq.drop_queue(queue_name); end;
    $f$;
    alter extension pgmq add function pgmq.drop_queue(text, boolean);
  end if;
end $$;
