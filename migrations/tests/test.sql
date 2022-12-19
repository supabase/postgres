CREATE EXTENSION IF NOT EXISTS pgtap;

BEGIN;

SELECT plan(13);

\ir fixtures.sql
\ir database/test.sql
\ir storage/test.sql

SELECT * FROM finish();

ROLLBACK;
