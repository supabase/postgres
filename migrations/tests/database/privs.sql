
SELECT database_privs_are(
    'postgres', 'postgres', ARRAY['CONNECT', 'TEMPORARY', 'CREATE']
);

SELECT function_privs_are('pgsodium', 'crypto_aead_det_decrypt', array['bytea', 'bytea', 'uuid', 'bytea'], 'service_role', array['EXECUTE']);
SELECT function_privs_are('pgsodium', 'crypto_aead_det_encrypt', array['bytea', 'bytea', 'uuid', 'bytea'], 'service_role', array['EXECUTE']);
SELECT function_privs_are('pgsodium', 'crypto_aead_det_keygen', array[]::text[], 'service_role', array['EXECUTE']);

set role postgres;
create table test_priv();
SELECT table_owner_is('test_priv', 'postgres');
SELECT table_privs_are('test_priv', 'supabase_admin', array['DELETE', 'INSERT', 'REFERENCES', 'SELECT', 'TRIGGER', 'TRUNCATE', 'UPDATE']);
SELECT table_privs_are('test_priv', 'anon', array['DELETE', 'INSERT', 'REFERENCES', 'SELECT', 'TRIGGER', 'TRUNCATE', 'UPDATE']);
SELECT table_privs_are('test_priv', 'authenticated', array['DELETE', 'INSERT', 'REFERENCES', 'SELECT', 'TRIGGER', 'TRUNCATE', 'UPDATE']);
SELECT table_privs_are('test_priv', 'service_role', array['DELETE', 'INSERT', 'REFERENCES', 'SELECT', 'TRIGGER', 'TRUNCATE', 'UPDATE']);
SELECT table_privs_are('test_priv', 'postgres', array['DELETE', 'INSERT', 'REFERENCES', 'SELECT', 'TRIGGER', 'TRUNCATE', 'UPDATE']);
reset role;
