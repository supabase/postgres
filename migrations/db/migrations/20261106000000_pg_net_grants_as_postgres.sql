-- migrate:up

-- pg_net grants used to be made by supabase_admin, and only the grantor can revoke a grant. So a
-- customer who wanted anon or authenticated out of net could not do it themselves. From now on
-- postgres is the grantor: supabase_admin gives postgres USAGE on net and EXECUTE on the http
-- functions WITH GRANT OPTION, and whatever anon, authenticated and service_role already hold is
-- granted again by postgres. New projects along with existing projects get the same three grants
-- from postgres.
--
-- extensions.apply_pg_net_grants() is the only place this happens. It runs here, on every CREATE
-- or ALTER EXTENSION pg_net through the event trigger below, and from complete.sh on upgrade, so
-- one piece of code covers init, restore and upgrade. It raises on failure: the callers below
-- decide whether that is fatal.

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

    -- Postgres records a superuser's GRANT as made by the object owner, supabase_admin. The grants
    -- below would get the wrong grantor and step 2 would then drop the only grant a role has.
    if exists (select from pg_roles where rolname = 'postgres' and rolsuper) then
        raise warning 'apply_pg_net_grants: postgres is a superuser, nothing changed';
        return;
    end if;

    -- Looked up by name, so a pg_net release that changes an argument list does not break this.
    select coalesce(array_agg(p.oid::regprocedure order by p.proname), '{}')
    into http_functions
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'net'
      and p.proname in ('http_get', 'http_post', 'http_delete');

    -- 1. postgres can grant onward.
    grant usage on schema net to postgres with grant option;
    foreach http_function in array http_functions loop
        execute format('grant execute on function %s to postgres with grant option', http_function);
    end loop;

    --    pg_net grants ALL on its tables to PUBLIC. TRIGGER there lets any role run code as the
    --    worker, which connects as postgres. postgres keeps TRIGGER for response handlers and
    --    TRUNCATE for clearing the queue.
    revoke trigger, references, truncate on all tables in schema net from public;
    grant trigger, truncate on all tables in schema net to postgres with grant option;

    -- 2. SET ROLE is not allowed inside CREATE EXTENSION, but a SECURITY DEFINER function owned by
    --    postgres is, and its grants are postgres's. Dropped and created on every run, so a superuser
    --    never calls a body the customer changed.
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

    --    On a fresh install, give the three roles USAGE as supabase_admin so the loop below converts
    --    them like an old project. pg_event_trigger_ddl_commands() only works inside an event trigger,
    --    so this runs for CREATE EXTENSION pg_net and raises everywhere else. Elsewhere a role without
    --    USAGE stays without: it may have been revoked (supabase support handling etc.) on purpose.
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

    --    USAGE on net is the switch. A role that holds it, from supabase_admin before the migration
    --    or from postgres after, gets the full set from postgres, so an extension update that drops
    --    and recreates a function is repaired too. Whatever supabase_admin granted the three roles
    --    goes, so a role support revoked, in full or in part, keeps nothing it cannot revoke itself.
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
    --    The helper added the row the customer can revoke. This removes the row they cannot, the
    --    one from supabase_admin.
    revoke usage on schema net from anon, authenticated, service_role;
    foreach http_function in array http_functions loop
        execute format('revoke execute on function %s from anon, authenticated, service_role', http_function);
    end loop;

    -- 3. Database Webhooks run as supabase_functions_admin. Its grants stay with supabase_admin,
    --    so a customer cannot break them, and it gets them here rather than through PUBLIC.
    if exists (select from pg_roles where rolname = 'supabase_functions_admin') then
        grant usage on schema net to supabase_functions_admin;
        foreach http_function in array http_functions loop
            execute format('grant execute on function %s to supabase_functions_admin', http_function);
        end loop;
    end if;
end;
$$;

revoke execute on function extensions.apply_pg_net_grants() from public, postgres;

-- The event trigger on CREATE EXTENSION used to grant the five roles itself, with the full
-- argument lists of http_get and http_post spelled out. Now it calls the routine. The routine
-- doesn't catches errors, so one here aborts the CREATE or ALTER EXTENSION and the customer sees
-- the message instead of a server log line.
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

-- An extension update can drop and recreate a function, which loses every grant on it.
drop event trigger if exists issue_pg_net_access;
create event trigger issue_pg_net_access
    on ddl_command_end
    when tag in ('CREATE EXTENSION', 'ALTER EXTENSION')
    execute procedure extensions.grant_pg_net_access();

-- Init and restore run this file with ON_ERROR_STOP, and complete.sh runs it on upgrade, so a
-- failed conversion is a warning here and the project keeps its current grants.
do $$
begin
    perform extensions.apply_pg_net_grants();
exception when others then
    raise warning 'apply_pg_net_grants: % (%)', sqlerrm, sqlstate;
end;
$$;

-- migrate:down
