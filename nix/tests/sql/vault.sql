SET ROLE service_role;

SELECT EXISTS (
  SELECT 1 FROM vault.create_secret('my_s3kre3t')
) AS can_create_secret;

SELECT EXISTS (
  SELECT 1 FROM vault.create_secret(
    'another_s3kre3t',
    'unique_name',
    'This is the description'
  )
) AS can_create_secret_with_params;

SELECT EXISTS (
  SELECT 1 FROM vault.secrets LIMIT 1
) AS can_select_from_secrets;

INSERT INTO vault.secrets (secret)
VALUES ('s3kre3t_k3y')
RETURNING EXISTS (
  SELECT 1
) AS can_insert_into_secrets;

SELECT EXISTS (
  SELECT name, description FROM vault.decrypted_secrets LIMIT 1
) AS can_select_from_decrypted_secrets;

INSERT INTO vault.secrets (secret) VALUES ('temp_secret_to_delete');

WITH deleted AS (
  DELETE FROM vault.secrets 
  WHERE secret = 'temp_secret_to_delete'
  RETURNING 1
)
SELECT EXISTS (SELECT 1 FROM deleted) AS can_delete_from_secrets;

INSERT INTO vault.secrets (secret) VALUES ('temp_secret_to_delete_from_decrypted');
WITH deleted AS (
  DELETE FROM vault.decrypted_secrets 
  WHERE secret = 'temp_secret_to_delete_from_decrypted'
  RETURNING 1
)
SELECT EXISTS (SELECT 1 FROM deleted) AS can_delete_from_decrypted_secrets;

WITH secret_id AS (
  SELECT id FROM vault.secrets ORDER BY created_at DESC LIMIT 1
)
SELECT EXISTS (
  SELECT 1 FROM vault.update_secret(
    (SELECT id FROM secret_id),
    'updated_secret'
  )
) AS can_update_secret;

WITH encrypted_value AS (
  SELECT secret FROM vault.secrets ORDER BY created_at DESC LIMIT 1
)
SELECT EXISTS (
  SELECT 1 FROM vault._crypto_aead_det_decrypt(
    decode((SELECT secret FROM encrypted_value), 'base64'),
    convert_to((SELECT id FROM vault.secrets ORDER BY created_at DESC LIMIT 1)::text, 'utf8'),
    0,
    'pgsodium'::bytea,
    (SELECT nonce FROM vault.secrets ORDER BY created_at DESC LIMIT 1)
  )
) AS can_decrypt;

RESET ROLE;
