create schema v;

create table v.samp(
  id int
);

select 1 from hypopg_create_index($$
  create index concurrently if not exists on v.samp(id)
$$);

drop schema v cascade;


