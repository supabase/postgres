select
  e.evtname,
  e.evtowner::regrole as evtowner,
  n_func.nspname as evtfunction_schema,
  e.evtfoid::regproc as evtfunction,
  p.proowner::regrole as function_owner
from pg_event_trigger e
join pg_proc p
  on e.evtfoid = p.oid
join pg_namespace n_func
  on p.pronamespace = n_func.oid
where p.prorettype = 'event_trigger'::regtype;

-- postgres can create event triggers
set role postgres;
create function f()
  returns event_trigger
  language plpgsql
  as $$ begin end $$;
create event trigger et
  on ddl_command_start
  execute function f();

drop event trigger et;
drop function f();
reset role;

-- supabase_etl_admin can create event triggers
set role supabase_etl_admin;
create schema s;
create function s.f()
  returns event_trigger
  language plpgsql
  as $$ begin end $$;
create event trigger et
  on ddl_command_start
  execute function s.f();

-- postgres can't drop supabase_etl_admin's event triggers
set role postgres;
drop event trigger et;

set role supabase_etl_admin;
drop event trigger et;
drop function s.f();
drop schema s;
reset role;
