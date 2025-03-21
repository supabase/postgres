-- migrate:up

-- Set up realtime
-- 1. Create publication supabase_realtime if it doesn't already exist
do $$
begin
  if not exists (
    select 1 from pg_catalog.pg_publication
    where pubname = 'supabase_realtime'
  )
  then
    create publication supabase_realtime;
  end if;
end
$$;

-- Supabase super admin
alter user supabase_admin with superuser createdb createrole replication bypassrls;

-- Supabase replication user
do $$
begin
  if not exists (
    select 1 from pg_roles
    where rolname = 'supabase_replication_admin'
  )
  then
    create user supabase_replication_admin with
      login
      replication;
  end if;
end
$$;

-- Supabase read-only user
do $$
begin
  if not exists (
    select 1 from pg_roles
    where rolname = 'supabase_read_only_user'
  )
  then
    create role supabase_read_only_user with
      login
      bypassrls;
  end if;
end
$$;
grant pg_read_all_data to supabase_read_only_user;

-- Extension namespacing
create schema if not exists extensions;
create extension if not exists "uuid-ossp"      with schema extensions;
create extension if not exists pgcrypto         with schema extensions;
create extension if not exists pgjwt            with schema extensions;

-- Set up auth roles for the developer
do $$
begin
  if not exists (
    select 1 from pg_roles
    where rolname = 'anon'
  )
  then
    create role anon nologin noinherit;
  end if;
end
$$;

-- "logged in" user: web_user, app_user, etc
do $$
begin
  if not exists (
    select 1 from pg_roles
    where rolname = 'authenticated'
  )
  then
    create role authenticated nologin noinherit;
  end if;
end
$$;

 -- allow developers to create JWT's that bypass their policies
do $$
begin
  if not exists (
    select 1 from pg_roles
    where rolname = 'service_role'
  )
  then
    create role service_role nologin noinherit bypassrls;
  end if;
end
$$;

do $$
begin
  if not exists (
    select 1 from pg_roles
    where rolname = 'authenticator'
  )
  then
    create role authenticator login noinherit;
  end if;
end
$$;


grant anon              to authenticator;
grant authenticated     to authenticator;
grant service_role      to authenticator;
grant supabase_admin    to authenticator;

grant usage                     on schema public to postgres, anon, authenticated, service_role;
alter default privileges in schema public grant all on tables to postgres, anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to postgres, anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to postgres, anon, authenticated, service_role;

-- Allow Extensions to be used in the API
grant usage                     on schema extensions to postgres, anon, authenticated, service_role;

-- Set up namespacing
alter user supabase_admin SET search_path TO public, extensions; -- don't include the "auth" schema

-- These are required so that the users receive grants whenever "supabase_admin" creates tables/function
alter default privileges for user supabase_admin in schema public grant all
    on sequences to postgres, anon, authenticated, service_role;
alter default privileges for user supabase_admin in schema public grant all
    on tables to postgres, anon, authenticated, service_role;
alter default privileges for user supabase_admin in schema public grant all
    on functions to postgres, anon, authenticated, service_role;

-- Set short statement/query timeouts for API roles
alter role anon set statement_timeout = '3s';
alter role authenticated set statement_timeout = '8s';

-- migrate:down
