-- enable JIT to ensure the upgrade process disables it
alter system set jit = on;
alter system set password_encryption = 'md5';
select pg_reload_conf();

-- create materialized view
create materialized view public.european_countries as
    select * from public.countries where continent = 'Europe'
with no data;
refresh materialized view public.european_countries;

select count(*) from public.european_countries;
