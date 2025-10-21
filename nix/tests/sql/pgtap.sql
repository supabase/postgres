begin;

set client_min_messages = warning;
create extension if not exists pgtap with schema extensions;

select plan(1);

-- Run the tests.
select pass( 'My test passed, w00t!' );

-- Finish the tests and clean up.
select * from finish();

rollback;
