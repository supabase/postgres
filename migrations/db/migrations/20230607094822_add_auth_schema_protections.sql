-- migrate:up

drop sequence if exists auth.changes_seq;

create sequence
  auth.changes_seq increment by 1;

comment on sequence auth.changes_seq is 'Tracks the number of changes of the auth schema.';

grant all on sequence
  auth.changes_seq
  to supabase_auth_admin
  with grant option;

drop sequence if exists auth.lock_seq;

create sequence
  auth.lock_seq increment by -1 no minvalue no maxvalue start with -1;
  -- starting off with protection disabled

comment on sequence auth.lock_seq is 'Used to protect against accidental schema changes in the auth schema.';

grant all on sequence
  auth.lock_seq
  to supabase_auth_admin
  with grant option;

create or replace function
  auth.enable_schema_ddl_protection()
  returns void
  language sql
  as $$
    alter sequence if exists auth.lock_seq increment by 1 no minvalue no maxvalue restart with 1;
  $$;

grant all on function
  auth.enable_schema_ddl_protection()
  to supabase_auth_admin
  with grant option;

create or replace function
  auth.disable_schema_ddl_protection()
  returns void
  language sql
  as $$
    alter sequence if exists auth.lock_seq increment by -1 no minvalue no maxvalue restart with -1;
  $$;

grant all on function
  auth.disable_schema_ddl_protection()
  to supabase_auth_admin
  with grant option;

create or replace function
  auth.schema_ddl_protection_command_end()
  returns event_trigger
  security definer
  language plpgsql
  as $$
    declare
      cmd record;
    begin
      for cmd in select * from pg_event_trigger_ddl_commands()
      loop
        if cmd.schema_name = 'auth' then
          if nextval('auth.lock_seq') > 0 then
            raise exception 'auth schema is protected from unintended changes. To unlock run SELECT auth.disable_schema_ddl_protection(); ';
          end if;

          perform nextval('auth.changes_seq');
        end if;
      end loop;
    end;
  $$;

drop event trigger if exists protect_auth_schema_ddl_command_end;
drop function if exists auth.schema_ddl_protection();

create or replace function
  auth.schema_ddl_protection_drop()
  returns event_trigger
  security definer
  language plpgsql
  as $$
    declare
      cmd record;
    begin
      for cmd in select * from pg_event_trigger_dropped_objects()
      loop
        if cmd.schema_name = 'auth' and cmd.object_identity not in ('auth.changes_seq', 'auth.lock_seq') then
          if nextval('auth.lock_seq') > 0 then
            raise exception 'auth schema is protected from unintended changes. To unlock run SELECT auth.disable_schema_ddl_protection(); ';
          end if;

          perform nextval('auth.changes_seq');
        end if;
      end loop;
    end;
  $$;

drop event trigger if exists protect_auth_schema_ddl_command_end cascade;

create event trigger
  protect_auth_schema_ddl_command_end
  on ddl_command_end
  execute function auth.schema_ddl_protection_command_end();

drop event trigger if exists protect_auth_schema_ddl_sql_drop cascade;

create event trigger
  protect_auth_schema_ddl_sql_drop
  on sql_drop
  execute function auth.schema_ddl_protection_drop();

-- migrate:down
