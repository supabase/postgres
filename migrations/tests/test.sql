-- Create all extensions
\ir extensions/test.sql

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT no_plan();

\ir fixtures.sql
\ir database/test.sql
\ir storage/test.sql

SELECT * FROM finish();

ROLLBACK;
