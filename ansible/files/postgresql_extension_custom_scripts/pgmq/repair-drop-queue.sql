-- one-time repair for pgmq installs that predate the drop_queue(text, boolean)
-- fix in after-create.sql: supautils only runs extension-custom-scripts on
-- CREATE EXTENSION, so any database that already ran CREATE EXTENSION pgmq
-- under the old hook is stuck without the 2-arg drop_queue and never picks up
-- the new hook on its own. Safe to run against an already-fixed install too.
do $$
begin
  if not exists (select from pg_extension where extname = 'pgmq') then
    return;
  end if;

  if to_regprocedure('pgmq.drop_queue(text)') is not null then
    alter extension pgmq drop function pgmq.drop_queue(text);
  end if;
  if to_regprocedure('pgmq.drop_queue(text, boolean)') is not null then
    alter extension pgmq drop function pgmq.drop_queue(text, boolean);
  end if;

  drop function if exists pgmq.drop_queue(text);
  drop function if exists pgmq.drop_queue(text, boolean);

  create function pgmq.drop_queue(queue_name text)
  returns boolean as $func$
  declare
      qtable text := pgmq.format_table_name(queue_name, 'q');
      qtable_seq text := qtable || '_msg_id_seq';
      fq_qtable text := 'pgmq.' || qtable;
      atable text := pgmq.format_table_name(queue_name, 'a');
      fq_atable text := 'pgmq.' || atable;
      partitioned boolean;
  begin
      execute format(
          $query$
          select is_partitioned from pgmq.meta where queue_name = %L
          $query$,
          queue_name
      ) into partitioned;

      if exists (
          select 1
          from pg_class c
          join pg_depend d on c.oid = d.objid
          join pg_extension e on d.refobjid = e.oid
          where c.relname = qtable and e.extname = 'pgmq'
      ) then
          execute format(
              $query$
              alter extension pgmq drop table pgmq.%I
              $query$,
              qtable
          );
      end if;

      if exists (
          select 1
          from pg_class c
          join pg_depend d on c.oid = d.objid
          join pg_extension e on d.refobjid = e.oid
          where c.relname = qtable_seq and e.extname = 'pgmq'
      ) then
          execute format(
              $query$
              alter extension pgmq drop sequence pgmq.%I
              $query$,
              qtable_seq
          );
      end if;

      if exists (
          select 1
          from pg_class c
          join pg_depend d on c.oid = d.objid
          join pg_extension e on d.refobjid = e.oid
          where c.relname = atable and e.extname = 'pgmq'
      ) then
          execute format(
              $query$
              alter extension pgmq drop table pgmq.%I
              $query$,
              atable
          );
      end if;

      execute format(
          $query$
          drop table if exists pgmq.%I
          $query$,
          qtable
      );

      execute format(
          $query$
          drop table if exists pgmq.%I
          $query$,
          atable
      );

      if exists (
          select 1
          from information_schema.tables
          where table_name = 'meta' and table_schema = 'pgmq'
      ) then
          execute format(
              $query$
              delete from pgmq.meta where queue_name = %L
              $query$,
              queue_name
          );
      end if;

      if partitioned then
          execute format(
            $query$
            delete from %I.part_config where parent_table in (%L, %L)
            $query$,
            pgmq._get_pg_partman_schema(), fq_qtable, fq_atable
          );
      end if;

      return true;
  end;
  $func$ language plpgsql;

  alter extension pgmq add function pgmq.drop_queue(text);

  create or replace function pgmq.drop_queue(queue_name text, partitioned boolean)
  returns boolean as $shim$
  begin
      return pgmq.drop_queue(queue_name);
  end;
  $shim$ language plpgsql;

  alter extension pgmq add function pgmq.drop_queue(text, boolean);
end $$;
