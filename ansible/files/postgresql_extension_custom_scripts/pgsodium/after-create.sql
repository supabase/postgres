grant execute on function pgsodium.crypto_aead_det_decrypt(pg_catalog.bytea, pg_catalog.bytea, pg_catalog.uuid, pg_catalog.bytea) to service_role;
grant execute on function pgsodium.crypto_aead_det_encrypt(pg_catalog.bytea, pg_catalog.bytea, pg_catalog.uuid, pg_catalog.bytea) to service_role;
grant execute on function pgsodium.crypto_aead_det_keygen to service_role;

CREATE OR REPLACE FUNCTION pgsodium.mask_role(masked_role pg_catalog.regrole, source_name pg_catalog.text, view_name pg_catalog.text)
RETURNS pg_catalog.void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp
AS $function$
BEGIN
  EXECUTE format(
    'GRANT SELECT ON pgsodium.key TO %s',
    masked_role);

  EXECUTE format(
    'GRANT pgsodium_keyiduser, pgsodium_keyholder TO %s',
    masked_role);

  EXECUTE format(
    'GRANT ALL ON %I TO %s',
    view_name,
    masked_role);
  RETURN;
END
$function$;
