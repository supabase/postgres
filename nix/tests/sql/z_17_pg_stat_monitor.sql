BEGIN;

set client_min_messages = warning;
create schema if not exists extensions;
create extension if not exists pg_stat_monitor with schema extensions;

select
  *
from
  extensions.pg_stat_monitor
where
  false;

ROLLBACK;
