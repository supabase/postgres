-- migrate:up

CREATE OR REPLACE FUNCTION extensions.pgrst_ddl_watch() RETURNS event_trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN SELECT * FROM pg_event_trigger_ddl_commands()
  LOOP
    IF cmd.command_tag IN (
      'CREATE SCHEMA', 'ALTER SCHEMA'
    , 'CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO', 'ALTER TABLE'
    , 'CREATE FOREIGN TABLE', 'ALTER FOREIGN TABLE'
    , 'CREATE VIEW', 'ALTER VIEW'
    , 'CREATE MATERIALIZED VIEW', 'ALTER MATERIALIZED VIEW'
    , 'CREATE FUNCTION', 'ALTER FUNCTION'
    , 'CREATE TYPE', 'ALTER TYPE'
    , 'CREATE RULE'
    , 'COMMENT'
    )
    -- don't notify in case of CREATE TEMP table or other objects created on pg_temp
    -- also exclude any objects inside Supabase schemas
    AND COALESCE(cmd.schema_name, '') NOT IN ('pg_temp', 'auth', 'realtime', '_realtime', 'storage')
    -- Exclude any trigger created on temp tables (object_identity = 'trigger on pg_temp.table')
    OR (cmd.command_tag = 'CREATE TRIGGER' AND cmd.object_identity NOT LIKE '% pg\_temp.%')
    THEN
      NOTIFY pgrst, 'reload schema';
    END IF;
  END LOOP;
END; $$;


CREATE OR REPLACE FUNCTION extensions.pgrst_drop_watch() RETURNS event_trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  obj record;
BEGIN
  FOR obj IN SELECT * FROM pg_event_trigger_dropped_objects()
  LOOP
    IF obj.object_type IN (
      'schema'
    , 'table'
    , 'foreign table'
    , 'view'
    , 'materialized view'
    , 'function'
    , 'type'
    , 'rule'
    )
    AND obj.is_temporary IS false -- no pg_temp objects
    -- also exclude any objects inside Supabase schemas
    AND COALESCE(obj.schema_name, '') NOT IN ('auth', 'realtime', '_realtime', 'storage')
    -- Exclude any trigger created on temp tables (object_identity = 'trigger on pg_temp.table')
    OR ( obj.object_type = 'trigger' AND obj.object_identity NOT LIKE '% pg\_temp.%')
    THEN
      NOTIFY pgrst, 'reload schema';
    END IF;
  END LOOP;
END; $$;

-- migrate:down
