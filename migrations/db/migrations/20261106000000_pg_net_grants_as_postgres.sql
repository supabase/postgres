-- migrate:up

-- Goal: let postgres manage who can use pg_net.
--
-- Until now the pg_net grants for anon, authenticated and service_role were made by
-- supabase_admin. A grant can be revoked by its grantor, a superuser, the object owner or a role
-- that inherits the grantor. The customer's postgres is none of those for a grant by
-- supabase_admin, so a customer who wanted one of those roles out of pg_net could not do it. This
-- led to a lot of support tickets. After this migration those grants come from postgres: the
-- customer can revoke them, and a role revoked by the customer stays revoked.
--
-- extensions.apply_pg_net_grants() is the routine which does all of it. It is the only place that
-- grants pg_net access. It runs:
--   - at the end of this file, for projects that already have pg_net,
--   - from the event trigger below, on every CREATE EXTENSION and ALTER EXTENSION pg_net,
--   - from complete.sh after a pg_upgrade, once postgres is no longer a superuser.
--
-- Different cases the routine handles:
--   - fresh install: the three roles, anon, authenticated and service_role, get USAGE on net and
--     EXECUTE on the http functions from postgres,
--   - existing project: what the three roles hold from supabase_admin is granted again by
--     postgres, then the supabase_admin grant is removed,
--   - a role that support or the customer revoked previously: the role holds no USAGE, so it gets
--     nothing,
--   - extension update that drops and recreates a function: roles that hold USAGE get EXECUTE on
--     the new function again,
--   - restore: the dump brings back the old grants, so this file runs after it and converts them
--     to the required privileges post restore.

create or replace function extensions.apply_pg_net_grants()
    returns void
    language plpgsql
    set search_path to pg_catalog, pg_temp
as $$
declare
    http_functions regprocedure[];
    http_function regprocedure;
    api_role name;
begin
    if not exists (select from pg_extension where extname = 'pg_net') then
        return;
    end if;

    -- When postgres is a superuser, Postgres records its GRANTs as made by the object owner, i.e.
    -- supabase_admin, so every grant below would get the wrong grantor and step 2 would then
    -- remove the only grant a role has. This is the state during restore and during pg_upgrade.
    -- Do nothing: the migration replay after restore and complete.sh after pg_upgrade run this
    -- again once postgres is demoted.
    if exists (select from pg_roles where rolname = 'postgres' and rolsuper) then
        raise warning 'apply_pg_net_grants: postgres is a superuser, nothing changed';
        return;
    end if;

    -- The http functions are found by name. Earlier the script found them by argument list, which
    -- breaks when pg_net changes one.
    select coalesce(array_agg(p.oid::regprocedure order by p.proname), '{}')
    into http_functions
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'net'
      and p.proname in ('http_get', 'http_post', 'http_delete');

    -- 1. postgres gets USAGE on the schema and EXECUTE on the http functions with grant option,
    --    so it can grant them onward and revoke them.
    grant usage on schema net to postgres with grant option;
    foreach http_function in array http_functions loop
        execute format('grant execute on function %s to postgres with grant option', http_function);
    end loop;

    --    pg_upgrade used to make http_get and http_post SECURITY DEFINER with search_path = net, so
    --    the API roles could queue a request on a pg_net that gave PUBLIC nothing on its tables.
    --    From 0.12.0 PUBLIC holds the table and sequence grants, so the functions run as the
    --    caller like on every other project, and a trigger on the queue no longer runs as the
    --    extension owner.
    if (select string_to_array(extversion, '.')::int[] >= array[0, 12, 0]
        from pg_extension where extname = 'pg_net') then
        foreach http_function in array http_functions loop
            execute format('alter function %s security invoker reset search_path', http_function);
        end loop;
    end if;

    --    pg_net 1.0.0 stops granting worker_restart to PUBLIC and leaves it to the extension owner.
    --    Here the owner is supabase_admin, and the customer administers pg_net as postgres: changes
    --    a setting, restarts the worker, brings it back when it died. So postgres gets it the same
    --    way as the http functions, with grant option, so it can hand it to its own roles.
    if to_regprocedure('net.worker_restart()') is not null then
        grant execute on function net.worker_restart() to postgres with grant option;
    end if;

    --    pg_net grants ALL on its tables to PUBLIC, including TRIGGER. A trigger on the queue runs
    --    as the worker, which connects as postgres, so no role other than postgres may create one.
    revoke trigger, references, truncate on all tables in schema net from public;
    grant trigger, truncate on all tables in schema net to postgres with grant option;

    -- 2. The three API roles get their grants from postgres.
    --
    --    This function runs as supabase_admin, and to make the grant work it should ideally be made
    --    by postgres. SET ROLE postgres will not work, as SET ROLE is not allowed inside CREATE
    --    EXTENSION on the Supabase platform. This restriction is added by supautils.
    --    So another way is a SECURITY DEFINER function. One owned by postgres can run there, and
    --    its grants are recorded as made by postgres. It is dropped and created on every run, so
    --    that a superuser never calls a function body the customer may have changed.
    drop function if exists extensions.grant_pg_net_api_access(name, regprocedure[]);
    create function extensions.grant_pg_net_api_access(api_role name, http_functions regprocedure[])
        returns void
        language plpgsql
        security definer
        set search_path to pg_catalog, pg_temp
    as $helper$
    begin
        execute format('grant usage on schema net to %I', api_role);
        if http_functions <> '{}' then
            execute format('grant execute on function %s to %I', array_to_string(http_functions, ', '), api_role);
        end if;
    end;
    $helper$;
    alter function extensions.grant_pg_net_api_access(name, regprocedure[]) owner to postgres;
    revoke execute on function extensions.grant_pg_net_api_access(name, regprocedure[]) from public;

    --    Fresh install: give the three roles USAGE as supabase_admin first, so the conversion below
    --    treats a new project exactly like an old one. pg_event_trigger_ddl_commands() works only
    --    inside an event trigger and raises anywhere else, which is how this block knows it runs
    --    for CREATE EXTENSION pg_net. In any other place a role without USAGE should stay without
    --    it, as support or the customer may have revoked it on purpose.
    begin
        perform from pg_event_trigger_ddl_commands() ev
        join pg_extension e on e.oid = ev.objid
        where ev.command_tag = 'CREATE EXTENSION' and e.extname = 'pg_net';
        if found then
            grant usage on schema net to anon, authenticated, service_role;
        end if;
    exception when event_trigger_protocol_violated then
        null;
    end;

    --    Conversion. Every API role that holds USAGE on net, from supabase_admin on an old project
    --    or from postgres on one already converted, gets USAGE and EXECUTE on the http functions
    --    from postgres. A role that holds no USAGE gets nothing. Running this on every extension
    --    update is what restores EXECUTE on a function the update recreated.
    for api_role in
        select distinct g.rolname
        from pg_namespace n
        cross join lateral aclexplode(n.nspacl) a
        join pg_roles g on g.oid = a.grantee
        where n.nspname = 'net'
          and a.privilege_type = 'USAGE'
          and a.grantor in ('supabase_admin'::regrole, 'postgres'::regrole)
          and g.rolname in ('anon', 'authenticated', 'service_role')
        order by g.rolname
    loop
        perform extensions.grant_pg_net_api_access(api_role, http_functions);
    end loop;
    --    Remove the supabase_admin grants. The grants from postgres added above stay, so the role
    --    keeps only what the customer can revoke.
    revoke usage on schema net from anon, authenticated, service_role;
    foreach http_function in array http_functions loop
        execute format('revoke execute on function %s from anon, authenticated, service_role', http_function);
    end loop;

    -- 3. Database Webhooks run as supabase_functions_admin. It keeps getting its grants from
    --    supabase_admin, so a customer cannot break webhooks by revoking them.
    if exists (select from pg_roles where rolname = 'supabase_functions_admin') then
        grant usage on schema net to supabase_functions_admin;
        foreach http_function in array http_functions loop
            execute format('grant execute on function %s to supabase_functions_admin', http_function);
        end loop;
    end if;
end;
$$;

revoke execute on function extensions.apply_pg_net_grants() from public, postgres;

-- The event trigger used to grant the five roles itself, with the argument lists of http_get and
-- http_post spelled out. Now it calls the routine. The routine does not catch errors, so a failure
-- aborts the CREATE or ALTER EXTENSION.
create or replace function extensions.grant_pg_net_access()
    returns event_trigger
    language plpgsql
    set search_path to pg_catalog, pg_temp
as $$
begin
    if not exists (
        select from pg_event_trigger_ddl_commands() ev
        join pg_extension e on ev.objid = e.oid
        where e.extname = 'pg_net'
    ) then
        return;
    end if;

    if not exists (select from pg_roles where rolname = 'supabase_functions_admin') then
        create user supabase_functions_admin noinherit createrole login noreplication;
    end if;

    perform extensions.apply_pg_net_grants();
end;
$$;

-- Fires on ALTER EXTENSION too: an extension update can drop and recreate a function, which loses
-- every grant on it, and the routine grants it again.
drop event trigger if exists issue_pg_net_access;
create event trigger issue_pg_net_access
    on ddl_command_end
    when tag in ('CREATE EXTENSION', 'ALTER EXTENSION')
    execute procedure extensions.grant_pg_net_access();

-- Everything above only defines the routine and the trigger. The trigger fires on the next CREATE
-- or ALTER EXTENSION pg_net, which on a project that already has pg_net may never happen. So run
-- the routine once here, to convert the grants that project holds today.
--
-- The exception block turns a failure into a warning on purpose. This file runs under
-- ON_ERROR_STOP: through dbmate at init and restore, and through complete.sh after pg_upgrade. An
-- error here would abort the whole run and leave the project half migrated or half upgraded. A
-- warning leaves it on its current grants, which still work, and the next CREATE or ALTER
-- EXTENSION runs the routine again.
do $$
begin
    perform extensions.apply_pg_net_grants();
exception when others then
    raise warning 'apply_pg_net_grants: % (%)', sqlerrm, sqlstate;
end;
$$;

-- migrate:down
