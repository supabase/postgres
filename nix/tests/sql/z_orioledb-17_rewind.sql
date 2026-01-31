-- Test OrioleDB rewind functionality
-- These tests verify the rewind feature interface and configuration
-- Note: Actual rewind operations require a server restart, so we only test
-- configuration and function existence here
--
-- Reference: https://github.com/orioledb/orioledb/blob/18a3029046ce70464d22bff6398885fa705aa54d/doc/usage/rewind.mdx

-- Verify rewind is enabled in configuration
SELECT name, setting FROM pg_settings
WHERE name LIKE 'orioledb.%rewind%'
ORDER BY name;

-- Verify rewind functions exist with correct signatures
SELECT
    p.proname AS function_name,
    pg_catalog.pg_get_function_result(p.oid) AS return_type,
    pg_catalog.pg_get_function_identity_arguments(p.oid) AS argument_types
FROM
    pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
WHERE
    p.proname LIKE 'orioledb_rewind%'
    OR p.proname LIKE 'orioledb_get_complete%'
    OR p.proname LIKE 'orioledb_get_current_oxid%'
    OR p.proname LIKE 'orioledb_get_rewind%'
ORDER BY
    p.proname;

-- Test diagnostic functions (these are read-only and safe)
SELECT orioledb_get_current_oxid() IS NOT NULL AS has_current_oxid;
SELECT orioledb_get_complete_xid() IS NOT NULL AS has_complete_xid;
SELECT orioledb_get_complete_oxid() IS NOT NULL AS has_complete_oxid;
SELECT orioledb_get_rewind_queue_length() >= 0 AS valid_queue_length;
SELECT orioledb_get_rewind_evicted_length() >= 0 AS valid_evicted_length;
