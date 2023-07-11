CREATE EXTENSION IF NOT EXISTS pgtap;

BEGIN;
SELECT plan(15);

select has_schema('public');
select has_schema('auth');
select has_schema('storage');
select has_schema('realtime');
select has_schema('pgsodium');
select has_schema('vault');
select has_schema('extensions');

SELECT has_enum('public', 'continents', 'Enum continents should exist');

SELECT has_table('public', 'countries', 'Table countries should exist');
SELECT has_column('public', 'countries', 'id', 'Column id should exist');
SELECT has_column('public', 'countries', 'name', 'Column name should exist');
SELECT has_column('public', 'countries', 'iso2', 'Column iso2 should exist');
SELECT has_column('public', 'countries', 'iso3', 'Column iso3 should exist');
SELECT has_column('public', 'countries', 'continent', 'Column continent should exist');

SELECT has_materialized_view('public', 'european_countries', 'Materialized view european_countries should exist');

SELECT * FROM finish();
ROLLBACK;
