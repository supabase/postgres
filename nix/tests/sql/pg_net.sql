BEGIN;

set client_min_messages = warning;
create extension if not exists pg_net with schema extensions;

-- This is a very basic test because you can't get the value returned
-- by a pg_net request in the same transaction that created it;

select
  net.http_get (
    'https://postman-echo.com/get?foo1=bar1&foo2=bar2'
  ) as request_id;

ROLLBACK;
