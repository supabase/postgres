-- Create all extensions
\ir extensions/test.sql

CREATE EXTENSION IF NOT EXISTS pgtap;

BEGIN;

SELECT plan(19);

\ir fixtures.sql
\ir database/test.sql
\ir storage/test.sql

SELECT * FROM finish();

ROLLBACK;
