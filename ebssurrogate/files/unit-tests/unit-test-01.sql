BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

DO $$ 
DECLARE
    extension_array text[];
    orioledb_available boolean;
BEGIN
    -- Check if orioledb is available
    SELECT EXISTS (
        SELECT 1 FROM pg_available_extensions WHERE name = 'orioledb'
    ) INTO orioledb_available;

    -- If available, create it and add to the expected extensions list
    IF orioledb_available THEN
        CREATE EXTENSION IF NOT EXISTS orioledb;
        extension_array := ARRAY[
            'plpgsql',
            'pg_stat_statements',
            'pgsodium',
            'pgtap',
            'pg_graphql',
            'pgcrypto',
            'pgjwt',
            'uuid-ossp',
            'supabase_vault',
            'orioledb'
        ];
    ELSE
        extension_array := ARRAY[
            'plpgsql',
            'pg_stat_statements',
            'pgsodium',
            'pgtap',
            'pg_graphql',
            'pgcrypto',
            'pgjwt',
            'uuid-ossp',
            'supabase_vault'
        ];
    END IF;

    -- Set the array as a temporary variable to use in the test
    PERFORM set_config('myapp.extensions', array_to_string(extension_array, ','), false);
END $$;

SELECT plan(8);

SELECT extensions_are(
    string_to_array(current_setting('myapp.extensions'), ',')::text[]
);


SELECT has_schema('pg_toast');
SELECT has_schema('pg_catalog');
SELECT has_schema('information_schema');
SELECT has_schema('public');

SELECT function_privs_are('pgsodium', 'crypto_aead_det_decrypt', array['bytea', 'bytea', 'uuid', 'bytea'], 'service_role', array['EXECUTE']);
SELECT function_privs_are('pgsodium', 'crypto_aead_det_encrypt', array['bytea', 'bytea', 'uuid', 'bytea'], 'service_role', array['EXECUTE']);
SELECT function_privs_are('pgsodium', 'crypto_aead_det_keygen', array[]::text[], 'service_role', array['EXECUTE']);

SELECT * FROM finish();
ROLLBACK;