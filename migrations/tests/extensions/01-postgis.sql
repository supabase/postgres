BEGIN;
create extension if not exists postgis_sfcgal with schema "extensions" cascade;
ROLLBACK;

BEGIN;
-- create postgis tiger as supabase_admin
create extension if not exists address_standardizer with schema extensions;
create extension if not exists postgis_tiger_geocoder cascade;
-- \ir ansible/files/postgresql_extension_custom_scripts/postgis_tiger_geocoder/after-create.sql
grant usage on schema tiger to postgres with grant option;
grant all privileges on all tables in schema tiger to postgres with grant option;
grant all privileges on all routines in schema tiger to postgres with grant option;
grant all privileges on all sequences in schema tiger to postgres with grant option;
alter default privileges in schema tiger grant all on tables to postgres with grant option;
alter default privileges in schema tiger grant all on routines to postgres with grant option;
alter default privileges in schema tiger grant all on sequences to postgres with grant option;
-- postgres role should have access
set local role postgres;
select tiger.pprint_addy(tiger.pagc_normalize_address('710 E Ben White Blvd, Austin, TX 78704'));
-- other roles can be granted access
grant usage on schema tiger to authenticated;
grant select on all tables in schema tiger to authenticated;
grant execute on all routines in schema tiger to authenticated;
-- authenticated role should have access now
set local role authenticated;
select tiger.pprint_addy(tiger.pagc_normalize_address('710 E Ben White Blvd, Austin, TX 78704'));
ROLLBACK;

BEGIN;
create extension if not exists address_standardizer_data_us with schema extensions;
set local role postgres;
select * from extensions.us_lex;
ROLLBACK;
