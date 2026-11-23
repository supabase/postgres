-- migrate:up

CREATE OR REPLACE FUNCTION extensions.pgrst_ddl_watch() RETURNS event_trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  cmd record;
  obj_schema text;
BEGIN
  FOR cmd IN SELECT * FROM pg_event_trigger_ddl_commands()
  LOOP
    -- triggers and rules have no schema of their own (schema_name is NULL),
    -- so use the schema of the table they belong to
    obj_schema := CASE
      WHEN cmd.object_type IN ('trigger', 'rule')
        THEN (pg_identify_object_as_address(cmd.classid, cmd.objid, cmd.objsubid)).object_names[1]
      ELSE cmd.schema_name
    END;

    IF cmd.command_tag IN (
      'CREATE SCHEMA', 'ALTER SCHEMA'
    , 'CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO', 'ALTER TABLE'
    , 'CREATE FOREIGN TABLE', 'ALTER FOREIGN TABLE'
    , 'CREATE VIEW', 'ALTER VIEW'
    , 'CREATE MATERIALIZED VIEW', 'ALTER MATERIALIZED VIEW'
    , 'CREATE FUNCTION', 'ALTER FUNCTION'
    , 'CREATE TRIGGER'
    , 'CREATE TYPE', 'ALTER TYPE'
    , 'CREATE RULE'
    , 'COMMENT'
    )
    -- don't notify in case of CREATE TEMP table or other objects created on pg_temp
    -- also exclude any objects inside Supabase schemas
    AND COALESCE(obj_schema, '') NOT IN ('pg_temp', 'auth', 'realtime', '_realtime', 'storage')
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
  obj_schema text;
BEGIN
  FOR obj IN SELECT * FROM pg_event_trigger_dropped_objects()
  LOOP
    -- triggers and rules have no schema of their own (schema_name is NULL),
    -- so use the schema of the table they belonged to
    obj_schema := CASE
      WHEN obj.object_type IN ('trigger', 'rule') THEN obj.address_names[1]
      ELSE obj.schema_name
    END;

    IF obj.object_type IN (
      'schema'
    , 'table'
    , 'foreign table'
    , 'view'
    , 'materialized view'
    , 'function'
    , 'trigger'
    , 'type'
    , 'rule'
    )
    AND obj.is_temporary IS false -- no pg_temp objects
    -- also exclude any objects inside Supabase schemas
    AND COALESCE(obj_schema, '') NOT IN ('pg_temp', 'auth', 'realtime', '_realtime', 'storage')
    THEN
      NOTIFY pgrst, 'reload schema';
    END IF;
  END LOOP;
END; $$;

-- migrate:down
