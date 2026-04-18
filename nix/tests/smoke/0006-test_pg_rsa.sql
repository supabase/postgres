-- File: 0006-test_pg_rsa.sql

begin;
    -- Plan for 3 tests: extension exists, function pg_rsa_test exists, and run pg_rsa_test
    select plan(3);
    
    -- Create the pg_rsa extension
    create extension if not exists pg_rsa;
    
    -- -- Test 1: Check if pg_rsa extension exists
    select has_extension('pg_rsa', 'The pg_rsa extension should exist.');
    
    -- -- Test 2: Check if the test function exists
    SELECT has_function('pg_rsa_test', 'The pg_rsa_test function should exist.');

    -- -- Test 3: Run the test function and check if it returns true
    SELECT ok(
        pg_rsa_test(),
        'pg_rsa_test() should return true.'
    );

    -- Finish the test plan
    select * from finish();
rollback;