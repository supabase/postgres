-- extensions.pgrst_ddl_watch / extensions.pgrst_drop_watch event triggers send
-- NOTIFY pgrst, 'reload schema' so PostgREST reloads its schema cache. They
-- must not fire for objects PostgREST never exposes:
--   * triggers created on / dropped from temporary tables
--   * objects created, altered or dropped in the Supabase-managed schemas
--     auth, realtime, _realtime and storage
--
-- Migration: 20260923021047_update_pgrst_watch_triggers.sql
--
-- NOTIFY is only delivered on commit, so every statement runs in autocommit
-- mode. A dblink side connection LISTENs on pgrst; pg_temp.pgrst_reloads()
-- returns how many notifications it received since the previous call. The
-- notifying backend PID is left out so the output is deterministic.

set client_min_messages = warning;

select public.dblink_connect(
  'pgrst_listener',
  format('host=localhost port=%s dbname=%s user=supabase_admin',
         current_setting('port'), current_database())
);
select public.dblink_exec('pgrst_listener', 'LISTEN pgrst');

create function pg_temp.pgrst_reloads() returns bigint
language plpgsql as $$
begin
  -- round trip so the listener has flushed any pending notification
  perform from public.dblink('pgrst_listener', 'SELECT 1') as t(x int);
  return (select count(*) from public.dblink_get_notify('pgrst_listener')
          where notify_name = 'pgrst' and extra = 'reload schema');
end $$;

-- Setup, notifications drained below. auth, realtime and storage come from
-- the migrations; _realtime is created by the Realtime service, not here.
create schema _realtime;
create schema pgrst_watch;
create function pgrst_watch.trg_fn() returns trigger
language plpgsql as $$ begin return new; end $$;
select pg_temp.pgrst_reloads() > 0 as setup_drained;

--------------------------------------------------------------------------------
-- pgrst_ddl_watch
--------------------------------------------------------------------------------

-- Positive controls: user-visible objects still trigger a reload.
create table pgrst_watch.t (id int);
select pg_temp.pgrst_reloads() as create_table;

create trigger t_trg before insert on pgrst_watch.t
  for each row execute function pgrst_watch.trg_fn();
select pg_temp.pgrst_reloads() as create_trigger;

alter table pgrst_watch.t add column name text;
select pg_temp.pgrst_reloads() as alter_table;

create view pgrst_watch.v as select id from pgrst_watch.t;
select pg_temp.pgrst_reloads() as create_view;

comment on table pgrst_watch.t is 'pgrst watch test';
select pg_temp.pgrst_reloads() as comment;

create rule t_rule as on update to pgrst_watch.t do instead nothing;
select pg_temp.pgrst_reloads() as create_rule;

-- Temporary objects: no reload.
create temp table tmp_t (id int);
select pg_temp.pgrst_reloads() as create_temp_table;

create trigger tmp_trg before insert on tmp_t
  for each row execute function pgrst_watch.trg_fn();
select pg_temp.pgrst_reloads() as create_trigger_on_temp_table;

alter table tmp_t add column name text;
select pg_temp.pgrst_reloads() as alter_temp_table;

-- Supabase schemas: no reload.
create table auth.pgrst_watch_t (id int);
select pg_temp.pgrst_reloads() as create_table_auth;

create table realtime.pgrst_watch_t (id int);
select pg_temp.pgrst_reloads() as create_table_realtime;

create table _realtime.pgrst_watch_t (id int);
select pg_temp.pgrst_reloads() as create_table__realtime;

create table storage.pgrst_watch_t (id int);
select pg_temp.pgrst_reloads() as create_table_storage;

alter table auth.pgrst_watch_t add column name text;
select pg_temp.pgrst_reloads() as alter_table_auth;

comment on table storage.pgrst_watch_t is 'pgrst watch test';
select pg_temp.pgrst_reloads() as comment_storage;

create view realtime.pgrst_watch_v as select id from realtime.pgrst_watch_t;
select pg_temp.pgrst_reloads() as create_view_realtime;

create function auth.pgrst_watch_fn() returns int language sql as 'select 1';
select pg_temp.pgrst_reloads() as create_function_auth;

create type storage.pgrst_watch_type as (a int);
select pg_temp.pgrst_reloads() as create_type_storage;

-- Triggers and rules have no schema_name of their own; the schema of their
-- table is used instead.
create rule realtime_rule as on update to realtime.pgrst_watch_t do instead nothing;
select pg_temp.pgrst_reloads() as create_rule_realtime;

create trigger auth_trg before insert on auth.pgrst_watch_t
  for each row execute function pgrst_watch.trg_fn();
select pg_temp.pgrst_reloads() as create_trigger_auth;

--------------------------------------------------------------------------------
-- pgrst_drop_watch
--------------------------------------------------------------------------------

-- Temporary objects: no reload.
drop trigger tmp_trg on tmp_t;
select pg_temp.pgrst_reloads() as drop_trigger_on_temp_table;

create trigger tmp_trg before insert on tmp_t
  for each row execute function pgrst_watch.trg_fn();
select pg_temp.pgrst_reloads() as recreate_trigger_on_temp_table;

-- dropping a temp table also drops its trigger
drop table tmp_t;
select pg_temp.pgrst_reloads() as drop_temp_table_with_trigger;

-- Supabase schemas: no reload.
drop function auth.pgrst_watch_fn();
select pg_temp.pgrst_reloads() as drop_function_auth;

drop type storage.pgrst_watch_type;
select pg_temp.pgrst_reloads() as drop_type_storage;

drop table _realtime.pgrst_watch_t;
select pg_temp.pgrst_reloads() as drop_table__realtime;

drop table storage.pgrst_watch_t;
select pg_temp.pgrst_reloads() as drop_table_storage;

-- dropping a view also drops its "_RETURN" rule
drop view realtime.pgrst_watch_v;
select pg_temp.pgrst_reloads() as drop_view_realtime;

drop rule realtime_rule on realtime.pgrst_watch_t;
select pg_temp.pgrst_reloads() as drop_rule_realtime;

drop trigger auth_trg on auth.pgrst_watch_t;
select pg_temp.pgrst_reloads() as drop_trigger_auth;

drop table auth.pgrst_watch_t;
select pg_temp.pgrst_reloads() as drop_table_auth;

drop table realtime.pgrst_watch_t;
select pg_temp.pgrst_reloads() as drop_table_realtime;

-- Positive controls: user-visible objects still trigger a reload.
drop rule t_rule on pgrst_watch.t;
select pg_temp.pgrst_reloads() as drop_rule;

drop trigger t_trg on pgrst_watch.t;
select pg_temp.pgrst_reloads() as drop_trigger;

drop view pgrst_watch.v;
select pg_temp.pgrst_reloads() as drop_view;

drop table pgrst_watch.t;
select pg_temp.pgrst_reloads() as drop_table;

drop schema pgrst_watch cascade;
select pg_temp.pgrst_reloads() as drop_schema;

-- Cleanup
drop schema _realtime;
select public.dblink_disconnect('pgrst_listener');
