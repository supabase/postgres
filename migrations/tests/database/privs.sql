SELECT database_privs_are(
    'postgres', 'postgres', ARRAY['CONNECT', 'TEMPORARY', 'CREATE']
);

SELECT function_privs_are('pgsodium', 'crypto_aead_det_decrypt', array['bytea', 'bytea', 'uuid', 'bytea'], 'service_role', array['EXECUTE']);
SELECT function_privs_are('pgsodium', 'crypto_aead_det_encrypt', array['bytea', 'bytea', 'uuid', 'bytea'], 'service_role', array['EXECUTE']);
SELECT function_privs_are('pgsodium', 'crypto_aead_det_keygen', array[]::text[], 'service_role', array['EXECUTE']);

-- Verify public schema privileges
SELECT schema_privs_are('public', 'postgres', array['CREATE', 'USAGE']);
SELECT schema_privs_are('public', 'anon', array['USAGE']);
SELECT schema_privs_are('public', 'authenticated', array['USAGE']);
SELECT schema_privs_are('public', 'service_role', array['USAGE']);

set role postgres;
create table test_priv();
SELECT table_owner_is('test_priv', 'postgres');
SELECT table_privs_are('test_priv', 'supabase_admin', array['DELETE', 'INSERT', 'REFERENCES', 'SELECT', 'TRIGGER', 'TRUNCATE', 'UPDATE']);
SELECT table_privs_are('test_priv', 'postgres', array['DELETE', 'INSERT', 'REFERENCES', 'SELECT', 'TRIGGER', 'TRUNCATE', 'UPDATE']);
SELECT table_privs_are('test_priv', 'anon', array['DELETE', 'INSERT', 'REFERENCES', 'SELECT', 'TRIGGER', 'TRUNCATE', 'UPDATE']);
SELECT table_privs_are('test_priv', 'authenticated', array['DELETE', 'INSERT', 'REFERENCES', 'SELECT', 'TRIGGER', 'TRUNCATE', 'UPDATE']);
SELECT table_privs_are('test_priv', 'service_role', array['DELETE', 'INSERT', 'REFERENCES', 'SELECT', 'TRIGGER', 'TRUNCATE', 'UPDATE']);
reset role;

-- Verify extensions schema privileges
SELECT schema_privs_are('extensions', 'postgres', array['CREATE', 'USAGE']);
SELECT schema_privs_are('extensions', 'anon', array['USAGE']);
SELECT schema_privs_are('extensions', 'authenticated', array['USAGE']);
SELECT schema_privs_are('extensions', 'service_role', array['USAGE']);

-- Role memberships
SELECT is_member_of('pg_read_all_data', 'postgres');
SELECT is_member_of('pg_signal_backend', 'postgres');
