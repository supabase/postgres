do $$
declare
  extoid oid := (select oid from pg_extension where extname = 'pgmq');
  r record;
  cls pg_class%rowtype;
begin

  set local search_path = '';
  update pg_extension set extowner = 'postgres'::regrole where extname = 'pgmq';

  for r in (select * from pg_depend where refobjid = extoid) loop


    if r.classid = 'pg_type'::regclass then

      -- store the type's relkind
      select * into cls from pg_class c where c.reltype = r.objid;

      if r.objid::regtype::text like '%[]' then
        -- do nothing (skipping array type)

      elsif cls.relkind in ('r', 'p', 'f', 'm') then
        -- table-like objects (regular table, partitioned, foreign, materialized view)
        execute format('alter table pgmq.%I owner to postgres;', cls.relname);

      else
        execute(format('alter type %s owner to postgres;', r.objid::regtype));

      end if;

    elsif r.classid = 'pg_proc'::regclass then
      execute(format('alter function %s(%s) owner to postgres;', r.objid::regproc, pg_get_function_identity_arguments(r.objid)));

    elsif r.classid = 'pg_class'::regclass then
      execute(format('alter table %s owner to postgres;', r.objid::regclass));

    else
      raise exception 'error on pgmq after-create script: unexpected object type %', r.classid;

    end if;
  end loop;
end $$;
