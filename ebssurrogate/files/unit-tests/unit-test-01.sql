BEGIN;
SELECT plan(8);

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

-- Check that service_role can execute certain pgsodium functions
SELECT function_privs_are('pgsodium', 'crypto_aead_det_decrypt', array['bytea', 'bytea', 'uuid', 'bytea'], 'service_role', array['EXECUTE']);
SELECT function_privs_are('pgsodium', 'crypto_aead_det_encrypt', array['bytea', 'bytea', 'uuid', 'bytea'], 'service_role', array['EXECUTE']);
SELECT function_privs_are('pgsodium', 'crypto_aead_det_keygen', array[]::text[], 'service_role', array['EXECUTE']);

SELECT * from finish();
ROLLBACK;
