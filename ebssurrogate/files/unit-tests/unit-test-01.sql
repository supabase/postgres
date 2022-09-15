BEGIN;
SELECT plan( 22 );

-- Check installed extensions
SELECT extensions_are(
    ARRAY[ 
    'plpgsql', 
    'pg_stat_statements', 
    'pgsodium',
    'uuid-ossp',
    'pgcrypto',
    'pgjwt',
    'pg_graphql',
    'pgtap' ]
);

-- Check schemas exists
SELECT has_schema('pg_toast');
SELECT has_schema('pg_catalog');
SELECT has_schema('information_schema');
SELECT has_schema('pgsodium');
SELECT has_schema('pgsodium_masks');
SELECT has_schema('public');
SELECT has_schema('extensions');
SELECT has_schema('storage');
SELECT has_schema('auth');
SELECT has_schema('realtime');
SELECT has_schema('graphql_public');
SELECT has_schema('graphql');

-- Check roles
SELECT has_role('anon');
SELECT has_role('dashboard_user');
SELECT has_role('service_role');
SELECT has_role('supabase_admin');
SELECT has_role('supabase_auth_admin');
SELECT has_role('supabase_storage_admin');

-- Check auth schema relations
SELECT fk_ok('auth','identities','user_id','auth','users','id');
SELECT fk_ok('auth','sessions','user_id','auth','users','id');

-- Check storage schema relations
SELECT fk_ok('storage','objects','bucket_id','storage','buckets','id');

SELECT * from finish();
ROLLBACK;
