BEGIN;
create extension if not exists postgis_sfcgal with schema "extensions" cascade;
ROLLBACK;
