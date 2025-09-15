-- migrate:up
create schema if not exists supabase_subscription_mgmt;
    
create or replace function supabase_subscription_mgmt.pg_create_subscription(
    arg_subscription_name text,
    arg_connection_string text,
    arg_publication_name text,
    arg_slot_name text,
    arg_copy_data boolean = true,
    arg_origin text = 'any'
)
returns void language plpgsql
security definer
set search_path = pg_catalog, supabase_subscription_mgmt
as $$
declare
  pg_version int;
  create_subscription_cmd text;
begin
  -- get the postgresql version
  select current_setting('server_version_num')::int into pg_version;

  if pg_version < 160000 and arg_origin <> 'any' then
    raise exception 'postgresql version must be 16 or higher to specify origin other than "any". current version: %', pg_version;
  end if;

  if arg_origin <> 'any' and arg_origin <> 'none' then
    raise exception 'invalid origin: %. origin must be either "any" or "none".', arg_origin;
  end if;

  -- pg16 and later: include the origin parameter only if it's 'none', as its default is any
  if pg_version >= 160000 and arg_origin = 'none' then
      create_subscription_cmd := pg_catalog.format(
        'create subscription %I connection %L publication %I with (slot_name=%L, create_slot=false, copy_data=%s, origin=%L)',
        arg_subscription_name, arg_connection_string, arg_publication_name, arg_slot_name, arg_copy_data::text, arg_origin);
 else
      create_subscription_cmd := pg_catalog.format(
        'create subscription %I connection %L publication %I with (slot_name=%L, create_slot=false, copy_data=%s)',
        arg_subscription_name, arg_connection_string, arg_publication_name, arg_slot_name, arg_copy_data::text);
  end if;

  -- execute the create subscription command
  execute create_subscription_cmd;
end;
$$;


create or replace function supabase_subscription_mgmt.pg_alter_subscription_disable(
  arg_subscription_name text
)
  returns void language plpgsql
  security definer
  set search_path = pg_catalog
as $$
begin
    execute pg_catalog.format('alter subscription %I disable', arg_subscription_name);
end;
$$;

create or replace function supabase_subscription_mgmt.pg_alter_subscription_enable(
  arg_subscription_name text
)
  returns void language plpgsql
  security definer
  set search_path = pg_catalog, supabase_subscription_mgmt
as $$
begin
    execute pg_catalog.format('alter subscription %I enable', arg_subscription_name);
end;
$$;

create or replace function supabase_subscription_mgmt.pg_drop_subscription(
    arg_subscription_name text
)
  returns void language plpgsql
  security definer
  set search_path = pg_catalog, supabase_subscription_mgmt
as $$
declare
    l_slot_name text;
    l_subconninfo text;
begin
    select subslotname, subconninfo
        into l_slot_name, l_subconninfo
        from pg_catalog.pg_subscription
        where subname = arg_subscription_name;
    if l_slot_name is null and l_subconninfo is null then
        raise exception 'no subscription found for name: %', arg_subscription_name;
    end if;
    execute pg_catalog.format('alter subscription %I disable', arg_subscription_name);
    execute pg_catalog.format('alter subscription %I set (slot_name = none)', arg_subscription_name);
    execute pg_catalog.format('drop subscription %I', arg_subscription_name);
end;
$$;

grant usage on schema supabase_subscription_mgmt to postgres;
grant execute on all functions in schema supabase_subscription_mgmt to postgres;

-- migrate:down

