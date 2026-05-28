-- Superuser-only extensions for testing.
--
-- These extensions are excluded from `supautils.privileged_extensions` (see
-- the "omitted because may be unsafe" comment in
-- `ansible/files/postgresql_config/supautils.conf.j2`). Hosted Supabase
-- projects cannot install them via non-superuser sessions, so this file is
-- loaded only by superuser-context harnesses: pg_regress (nix/checks.nix),
-- the docker-image-test, and the local migrate-tool. supadev's hosted
-- engines-with-smoke test sources `prime.sql` only.
--
-- This file covers the "may be unsafe" extensions available in BOTH PG 15
-- and PG 17 builds. Two more entries from the same list, `adminpack` and
-- `old_snapshot`, were removed from contrib in PG 17 and are loaded directly
-- by nix/tests/sql/z_15_ext_interface.sql for the PG 15 path.
--
-- Keep this list in sync with the "may be unsafe" list in supautils.conf.j2,
-- minus adminpack and old_snapshot.

set client_min_messages = warning;

create extension if not exists amcheck;
create extension if not exists file_fdw;
create extension if not exists lo;
create extension if not exists pageinspect;
create extension if not exists pg_freespacemap;
create extension if not exists pg_surgery;
create extension if not exists pg_visibility;
