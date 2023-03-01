BEGIN;
-- create repack as supabase_admin
create extension if not exists pg_repack with schema "extensions";

-- \ir ansible/files/postgresql_extension_custom_scripts/pg_repack/after-create.sql
grant usage on schema repack to postgres with grant option;
grant all on all tables in schema repack to postgres with grant option;
grant all on all routines in schema repack to postgres with grant option;
grant all on all sequences in schema repack to postgres with grant option;
alter default privileges in schema repack grant all on tables to postgres with grant option;
alter default privileges in schema repack grant all on routines to postgres with grant option;
alter default privileges in schema repack grant all on sequences to postgres with grant option;

-- postgres role should have access
set local role postgres;
select repack.version();

-- other roles can be granted access
grant usage on schema repack to authenticated;
grant select on all tables in schema repack to authenticated;
grant execute on all routines in schema repack to authenticated;

-- authenticated role should have access now
set local role authenticated;
select repack.version();
ROLLBACK;
