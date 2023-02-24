grant usage on schema tiger to postgres with grant option;

grant all on all tables in schema tiger to postgres with grant option;
grant all on all routines in schema tiger to postgres with grant option;
grant all on all sequences in schema tiger to postgres with grant option;

alter default privileges in schema tiger grant all on tables to postgres with grant option;
alter default privileges in schema tiger grant all on routines to postgres with grant option;
alter default privileges in schema tiger grant all on sequences to postgres with grant option;
