CREATE EXTENSION IF NOT EXISTS pgtap;

BEGIN;
SELECT plan(1);

SELECT results_eq(
    'SELECT count(*)::integer FROM pg_settings where name = ''jit'' and setting = ''off''',
    ARRAY[ 1 ]
);

SELECT * FROM finish();
ROLLBACK;
