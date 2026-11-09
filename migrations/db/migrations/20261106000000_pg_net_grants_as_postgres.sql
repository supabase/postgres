-- migrate:up

-- pg_net grants used to be made by supabase_admin, and only the grantor can revoke a grant. So a
-- customer who wanted anon or authenticated out of net could not do it themselves. From now on
-- postgres is the grantor: supabase_admin gives postgres USAGE on net and EXECUTE on the http
-- functions WITH GRANT OPTION, and whatever anon, authenticated and service_role already hold is
-- granted again by postgres. New projects get no grants for those three roles at all. They still
-- reach net through PUBLIC, which pg_net's own install script grants, until pg_net stops doing so.
--
-- extensions.apply_pg_net_grants() is the one place this happens. It runs here and on every
-- CREATE EXTENSION pg_net through the event trigger below. The upgrade scripts are next, so one
-- piece of code covers init, restore and upgrade. It never raises: init and restore run with
-- ON_ERROR_STOP.

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

    -- 2. A role that still holds the old direct grant from supabase_admin keeps its access, now
    --    granted by postgres, and the supabase_admin grant goes. A role support already revoked by
    --    hand has no direct grant and gets nothing. Postgres does not allow SET ROLE inside
    --    CREATE EXTENSION, but a fresh install has no direct grants, so this loop is empty there.
    for api_role in
        select g.rolname
        from pg_namespace n
        cross join lateral aclexplode(n.nspacl) a
        join pg_roles g on g.oid = a.grantee
        join pg_roles o on o.oid = a.grantor
        where n.nspname = 'net'
          and a.privilege_type = 'USAGE'
          and o.rolname = 'supabase_admin'
          and g.rolname in ('anon', 'authenticated', 'service_role')
        order by g.rolname
    loop
        set local role postgres;
        execute format('grant usage on schema net to %I', api_role);
        foreach http_function in array http_functions loop
            execute format('grant execute on function %s to %I', http_function, api_role);
        end loop;
        reset role;
        execute format('revoke usage on schema net from %I', api_role);
        foreach http_function in array http_functions loop
            execute format('revoke execute on function %s from %I', http_function, api_role);
        end loop;
    end loop;

    -- 3. Database Webhooks run as supabase_functions_admin. Its grants stay with supabase_admin,
    --    so a customer cannot break them, and it gets them here rather than through PUBLIC.
    if exists (select from pg_roles where rolname = 'supabase_functions_admin') then
        grant usage on schema net to supabase_functions_admin;
        foreach http_function in array http_functions loop
            execute format('grant execute on function %s to supabase_functions_admin', http_function);
        end loop;
    end if;
exception when others then
    raise warning 'apply_pg_net_grants: % (%)', sqlerrm, sqlstate;
end;
$$;

revoke execute on function extensions.apply_pg_net_grants() from public, postgres;

-- The event trigger on CREATE EXTENSION used to grant the five roles itself, with the full
-- argument lists of http_get and http_post spelled out. Now it calls the routine.
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

select extensions.apply_pg_net_grants();

-- migrate:down
