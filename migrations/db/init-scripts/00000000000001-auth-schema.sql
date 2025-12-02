-- migrate:up

CREATE SCHEMA IF NOT EXISTS auth AUTHORIZATION supabase_admin;

-- usage on auth functions to API roles
GRANT USAGE ON SCHEMA auth TO anon, authenticated, service_role;

-- Supabase super admin
CREATE USER supabase_auth_admin NOINHERIT CREATEROLE LOGIN NOREPLICATION;
GRANT ALL PRIVILEGES ON SCHEMA auth TO supabase_auth_admin;
ALTER USER supabase_auth_admin SET search_path = "auth";

-- migrate:down
