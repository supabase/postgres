-- migrate:up

ALTER table IF EXISTS "auth".users OWNER TO supabase_auth_admin;
ALTER table IF EXISTS "auth".refresh_tokens OWNER TO supabase_auth_admin;
ALTER table IF EXISTS "auth".audit_log_entries OWNER TO supabase_auth_admin;
ALTER table IF EXISTS "auth".instances OWNER TO supabase_auth_admin;
ALTER table IF EXISTS "auth".schema_migrations OWNER TO supabase_auth_admin;

-- update auth schema permissions
do $$
begin
  if exists (select from pg_namespace where nspname = 'auth') then
    GRANT ALL PRIVILEGES ON SCHEMA auth TO supabase_auth_admin;
    GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA auth TO supabase_auth_admin;
    GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA auth TO supabase_auth_admin;

    GRANT USAGE ON SCHEMA auth TO postgres;
    GRANT ALL ON ALL TABLES IN SCHEMA auth TO postgres;
    GRANT ALL ON ALL SEQUENCES IN SCHEMA auth TO postgres;
    GRANT ALL ON ALL ROUTINES IN SCHEMA auth TO postgres;

    -- ALTER DEFAULT PRIVILEGES FOR ROLE supabase_auth_admin IN SCHEMA auth GRANT ALL ON TABLES TO postgres;
    -- ALTER DEFAULT PRIVILEGES FOR ROLE supabase_auth_admin IN SCHEMA auth GRANT ALL ON SEQUENCES TO postgres;
    -- ALTER DEFAULT PRIVILEGES FOR ROLE supabase_auth_admin IN SCHEMA auth GRANT ALL ON ROUTINES TO postgres;
  end if;
end $$;

-- migrate:down
