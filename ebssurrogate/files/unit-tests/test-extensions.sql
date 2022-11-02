CREATE OR REPLACE FUNCTION install_available_extensions_and_test() RETURNS boolean AS $$
DECLARE extension_name TEXT;
name TEXT;
allowed_extentions TEXT[] := string_to_array(current_setting('supautils.privileged_extensions'), ',');
BEGIN 
  FOREACH extension_name IN ARRAY allowed_extentions 
  LOOP
    RAISE notice '%', extension_name;
    SELECT trim(extension_name) INTO extension_name;
    EXECUTE format('DROP EXTENSION IF EXISTS %s CASCADE', quote_ident(extension_name));
    EXECUTE format('CREATE EXTENSION %s CASCADE', quote_ident(extension_name));
  END LOOP;
return true;
END;
$$ LANGUAGE plpgsql;
