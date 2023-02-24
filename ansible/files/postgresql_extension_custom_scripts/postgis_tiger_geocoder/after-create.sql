grant usage on schema tiger, tiger_data to postgres with grant option;

grant all on all tables in schema tiger, tiger_data to postgres with grant option;
grant all on all routines in schema tiger, tiger_data to postgres with grant option;
grant all on all sequences in schema tiger, tiger_data to postgres with grant option;

alter default privileges in schema tiger, tiger_data grant all on tables to postgres with grant option;
alter default privileges in schema tiger, tiger_data grant all on routines to postgres with grant option;
alter default privileges in schema tiger, tiger_data grant all on sequences to postgres with grant option;
