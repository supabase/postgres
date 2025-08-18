-- Test VERSION restriction for non-superuser accounts
-- First, ensure pg_net is not installed
DROP EXTENSION IF EXISTS pg_net CASCADE;

-- Test 1: postgres user (non-superuser) should be blocked from specifying VERSION
-- This should raise an error
DO $$
BEGIN
  -- Try to create extension with specific version as postgres user
  -- This should fail with our custom error message
  BEGIN
    EXECUTE 'CREATE EXTENSION pg_net WITH SCHEMA extensions VERSION ''0.14.0''';
    RAISE EXCEPTION 'Test failed: postgres user was able to specify VERSION when it should have been blocked';
  EXCEPTION
    WHEN OTHERS THEN
      -- Expected error message should contain our custom message
      IF SQLERRM NOT LIKE '%Only administrators can specify VERSION when creating extensions%' THEN
        RAISE EXCEPTION 'Test failed: Unexpected error message: %', SQLERRM;
      END IF;
      RAISE NOTICE 'Test 1 passed: postgres user correctly blocked from specifying VERSION';
  END;
END $$;

-- Test 2: postgres user should be able to create extension WITHOUT specifying VERSION
CREATE EXTENSION pg_net WITH SCHEMA extensions;

-- Verify the default version was installed (not the old version)
DO $$
DECLARE
  installed_version text;
BEGIN
  SELECT extversion INTO installed_version 
  FROM pg_extension 
  WHERE extname = 'pg_net';
  
  IF installed_version = '0.14.0' THEN
    RAISE EXCEPTION 'Test failed: Old version was installed when default should have been used';
  END IF;
  
  RAISE NOTICE 'Test 2 passed: postgres user created extension with default version %', installed_version;
END $$;

-- Clean up for next test
DROP EXTENSION pg_net;

-- Test 3: supabase_admin should be able to specify VERSION
-- First, we need to switch to supabase_admin role
SET ROLE supabase_admin;

-- Create extension with specific old version
CREATE EXTENSION pg_net WITH SCHEMA extensions VERSION '0.14.0';

-- Verify the specified version was installed
DO $$
DECLARE
  installed_version text;
BEGIN
  SELECT extversion INTO installed_version 
  FROM pg_extension 
  WHERE extname = 'pg_net';
  
  IF installed_version != '0.14.0' THEN
    RAISE EXCEPTION 'Test failed: Version % was installed instead of requested 0.14.0', installed_version;
  END IF;
  
  RAISE NOTICE 'Test 3 passed: supabase_admin successfully specified VERSION 0.14.0';
END $$;

-- Reset role back to postgres
RESET ROLE;

-- Clean up and reinstall with default version for the actual pg_net test
DROP EXTENSION pg_net;
CREATE EXTENSION pg_net WITH SCHEMA extensions;

-- This is a very basic test because you can't get the value returned
-- by a pg_net request in the same transaction that created it;

select
  net.http_get (
    'https://postman-echo.com/get?foo1=bar1&foo2=bar2'
  ) as request_id;
