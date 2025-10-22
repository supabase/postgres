BEGIN;

set client_min_messages = warning;
create extension if not exists hypopg with schema extensions;

create schema v;

create table v.samp(
  id int
);

select 1 from hypopg_create_index($$
  create index on v.samp(id)
$$);

drop schema v cascade;

ROLLBACK;


