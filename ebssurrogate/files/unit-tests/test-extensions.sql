CREATE OR REPLACE FUNCTION install_available_extensions_and_test() RETURNS boolean AS $$
DECLARE extension_name TEXT;
allowed_extentions TEXT[] := string_to_array(current_setting('supautils.privileged_extensions'), ',');
BEGIN 
  FOREACH extension_name IN ARRAY allowed_extentions 
  LOOP
    SELECT trim(extension_name) INTO extension_name;
    /* skip below extensions check for now */
    CONTINUE WHEN extension_name = 'pgroonga' OR  extension_name = 'pgroonga_database' OR extension_name = 'pgsodium';
    CONTINUE WHEN extension_name = 'plpgsql' OR  extension_name = 'plpgsql_check' OR extension_name = 'pgtap';
    CONTINUE WHEN extension_name = 'supabase_vault';
    RAISE notice 'START TEST FOR: %', extension_name;
    EXECUTE format('DROP EXTENSION IF EXISTS %s CASCADE', quote_ident(extension_name));
    EXECUTE format('CREATE EXTENSION %s CASCADE', quote_ident(extension_name));
    RAISE notice 'END TEST FOR: %', extension_name;
  END LOOP;
    RAISE notice 'EXTENSION TESTS COMPLETED..';
    return true;
END;
$$ LANGUAGE plpgsql;
