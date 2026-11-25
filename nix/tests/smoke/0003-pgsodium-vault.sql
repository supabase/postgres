BEGIN;

select plan(4);

select id as test_new_key_id from pgsodium.create_key(name:='test_new_key') \gset

select vault.create_secret (
	's3kr3t_k3y', 'a_name', 'this is the foo secret key') test_secret_id \gset

-- supabase_vault 0.3.0+ ignores the key id argument (it is kept for backward
-- compatibility): every secret is encrypted with the internal key (key_id 0)
-- and the stored key_id is NULL.
select vault.create_secret (
	's3kr3t_k3y_2', 'another_name', 'this is another foo key',
	(select id from pgsodium.key where name = 'test_new_key')) test_secret_id_2 \gset

SELECT results_eq(
    $$
    SELECT decrypted_secret = 's3kr3t_k3y', description = 'this is the foo secret key'
    FROM vault.decrypted_secrets WHERE name = 'a_name';
    $$,
    $$VALUES (true, true)$$,
    'can select from masking view with default key');

SELECT results_eq(
    $$
    SELECT decrypted_secret = 's3kr3t_k3y_2', description = 'this is another foo key'
    FROM vault.decrypted_secrets WHERE name = 'another_name';
    $$,
    $$VALUES (true, true)$$,
    'can select from masking view for a secret created with a key id argument');

SELECT is(
    (SELECT key_id FROM vault.secrets WHERE name = 'another_name'),
    NULL,
    'stored key_id is NULL since the key id argument is unused (vault 0.3.0+)');

SELECT lives_ok(
	format($test$
	select vault.update_secret(
	    %L::uuid, new_name:='a_new_name',
	    new_secret:='new_s3kr3t_k3y', new_description:='this is the bar key')
	$test$, :'test_secret_id'),
	'can update name, secret and description'
	);

SELECT * FROM finish();
ROLLBACK;
