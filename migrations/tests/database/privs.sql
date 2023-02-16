
SELECT database_privs_are(
    'postgres', 'postgres', ARRAY['CONNECT', 'TEMPORARY', 'CREATE']
);

SELECT function_privs_are('pgsodium', 'crypto_aead_det_decrypt', array['bytea', 'bytea', 'uuid', 'bytea'], 'service_role', array['EXECUTE']);
SELECT function_privs_are('pgsodium', 'crypto_aead_det_encrypt', array['bytea', 'bytea', 'uuid', 'bytea'], 'service_role', array['EXECUTE']);
SELECT function_privs_are('pgsodium', 'crypto_aead_det_keygen', array[]::text[], 'service_role', array['EXECUTE']);
