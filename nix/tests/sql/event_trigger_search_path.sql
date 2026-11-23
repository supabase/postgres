-- Regression test: every Supabase-owned event trigger function must pin search_path.
--
-- Event triggers fire as superuser on DDL run by any role, so an event trigger function
-- that resolves names through the caller's search_path can be hijacked by objects the
-- caller creates. A migration that redefines one of these functions with CREATE OR REPLACE
-- and omits the SET clause silently drops the pin (this happened with
-- 20260923021047_update_pgrst_watch_triggers.sql).
--
-- The pin must be exactly `pg_catalog, pg_temp`. An empty search_path is NOT enough: when
-- pg_temp is not listed it is searched first for relation and type names, so a caller's
-- `create temp table pg_extension (...)` would shadow the catalog. Listing pg_temp
-- explicitly moves it last. Extension-owned event triggers are excluded: their functions
-- ship with the extension and are not ours to change.
-- Silent on success, raises on regression.
do $$
declare
  _checked int;
  _offenders text;
begin
  -- Event triggers are per-database. Only the pg_regress database ('postgres') has the
  -- migrations applied; the pgtap pass runs this file against a bare 'testing' database.
  if current_database() <> 'postgres' then
    return;
  end if;

  with supabase_event_triggers as (
    select e.evtname, p.oid as fn, p.proconfig
    from pg_event_trigger e
    join pg_proc p on p.oid = e.evtfoid
    where not exists (
      select from pg_depend d
      where d.deptype = 'e'
        and (
          (d.classid = 'pg_event_trigger'::regclass and d.objid = e.oid)
          or (d.classid = 'pg_proc'::regclass and d.objid = p.oid)
        )
    )
  )
  select
    count(*),
    string_agg(
      format('%s -> %s', evtname, fn::regprocedure),
      ', ' order by evtname
    ) filter (where not ('search_path=pg_catalog, pg_temp' = any(coalesce(proconfig, '{}'))))
  into _checked, _offenders
  from supabase_event_triggers;

  -- guard against the query silently matching nothing
  if _checked < 6 then
    raise exception 'expected at least 6 Supabase event triggers, found %', _checked;
  end if;

  if _offenders is not null then
    raise exception 'event trigger functions without SET search_path TO pg_catalog, pg_temp: %', _offenders;
  end if;
end
$$;
