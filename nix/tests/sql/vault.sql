SET ROLE postgres;

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

DO $$
BEGIN
  INSERT INTO vault.secrets (secret)
  VALUES ('s3kre3t_k3y');
  EXCEPTION WHEN insufficient_privilege THEN RETURN;
  RAISE EXCEPTION 'should not be able to insert into vault.secrets';
END;
$$ LANGUAGE PLPGSQL;

SELECT EXISTS (
  SELECT * FROM vault.decrypted_secrets LIMIT 1
) AS can_select_from_decrypted_secrets;

SELECT vault.create_secret('s', new_name := 'temp_secret_to_delete') IS NOT NULL; 
WITH deleted AS (
  DELETE FROM vault.secrets
  WHERE name = 'temp_secret_to_delete'
  RETURNING 1
)
SELECT EXISTS (SELECT 1 FROM deleted) AS can_delete_from_secrets;

SELECT vault.create_secret('temp_secret_to_delete_from_decrypted') IS NOT NULL;
WITH deleted AS (
  DELETE FROM vault.decrypted_secrets 
  WHERE decrypted_secret = 'temp_secret_to_delete_from_decrypted'
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

DO $$
BEGIN
  INSERT INTO vault.secrets (secret)
  VALUES ('s3kre3t_k3y');
  EXCEPTION WHEN insufficient_privilege THEN RETURN;
  RAISE EXCEPTION 'should not be able to insert into vault.secrets';
END;
$$ LANGUAGE PLPGSQL;

SELECT EXISTS (
  SELECT name, description FROM vault.decrypted_secrets LIMIT 1
) AS can_select_from_decrypted_secrets;

SELECT vault.create_secret('', new_name := 'temp_secret_to_delete') IS NOT NULL; 
WITH deleted AS (
  DELETE FROM vault.secrets
  WHERE name = 'temp_secret_to_delete'
  RETURNING 1
)
SELECT EXISTS (SELECT 1 FROM deleted) AS can_delete_from_secrets;

SELECT vault.create_secret('temp_secret_to_delete_from_decrypted') IS NOT NULL;
WITH deleted AS (
  DELETE FROM vault.decrypted_secrets 
  WHERE decrypted_secret = 'temp_secret_to_delete_from_decrypted'
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

RESET ROLE;
