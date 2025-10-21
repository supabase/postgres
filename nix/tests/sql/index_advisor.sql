BEGIN;

set client_min_messages = warning;
create extension if not exists hypopg with schema extensions;
create extension if not exists index_advisor with schema extensions;

create schema v;

create table v.book(
  id int primary key,
  title text not null
);

select
  index_statements, errors
from
  index_advisor('select id from v.book where title = $1');

drop schema v cascade;

ROLLBACK;
