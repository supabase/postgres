-- Prime script for production-like setup (Phase 2: pg_regress tests)
-- This matches the initial state of a production Supabase instance
-- Only the default extensions that are enabled on project deployment are created here
-- All other extensions are created by individual test files within BEGIN/ROLLBACK blocks

-- disable notice messages because they differ between 15 and 17
set client_min_messages = warning;

-- Production default extensions (enabled on every new Supabase project)
-- These match what customers see when their project is first deployed

create extension if not exists "uuid-ossp" with schema extensions;
create extension if not exists pgcrypto with schema extensions;
create extension if not exists pg_graphql with schema graphql;
create extension if not exists pg_stat_statements with schema extensions;

-- Additional extensions commonly used in production that need security vetting
-- These create SECURITY DEFINER functions that must be validated by the security test
create extension if not exists dblink with schema extensions;
create extension if not exists pgaudit with schema extensions;
create extension if not exists postgis with schema extensions;
create extension if not exists pg_repack with schema extensions;

-- pgsodium is non-relocatable (schema = pgsodium) and creates SECURITY DEFINER functions
-- Note: vault 0.3.0+ removed pgsodium dependency, so migration only creates pgsodium for vault 0.2.8
-- We create it here explicitly for testing pgsodium's SECURITY DEFINER functions
create extension if not exists pgsodium;

-- Note: plpgsql is already installed by default in PostgreSQL (pg_catalog schema)
-- Note: supabase_vault is created by migrations (20221207154255_create_pgsodium_and_vault.sql)
