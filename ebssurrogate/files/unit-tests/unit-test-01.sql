BEGIN;
SELECT plan( 5 );

-- Check installed extensions
SELECT extensions_are(
    ARRAY[
    'plpgsql',
    'pg_stat_statements',
    'pgsodium',
    'pgtap',
    'pg_graphql',
    'pgcrypto',
    'pgjwt',
    'uuid-ossp'
     ]
);


-- Check schemas exists
SELECT has_schema('pg_toast');
SELECT has_schema('pg_catalog');
SELECT has_schema('information_schema');
SELECT has_schema('public');

SELECT * from finish();
ROLLBACK;
