select pg_is_in_recovery() as replica \gset
\if :replica
\quit
\endif

create temp view stale as
select datname,
       string_to_array(datcollversion, '.')::int[] between string_to_array('@minGlibc@', '.')::int[] and string_to_array('@maxGlibc@', '.')::int[]
       and string_to_array(pg_database_collation_actual_version(oid), '.')::int[] between string_to_array('@minGlibc@', '.')::int[] and string_to_array('@maxGlibc@', '.')::int[] as in_bounds
from pg_database
where datlocprovider = 'c'
  and datcollate in ('en_US.UTF-8', 'en_US.utf8')
  and datcollversion is not null
  and datcollversion <> pg_database_collation_actual_version(oid);

\set ON_ERROR_STOP off
select format('alter database %I refresh collation version', datname) from stale where in_bounds order by datname
\gexec

\set ON_ERROR_STOP on
do $$ begin
  if exists (select from stale) then
    raise exception 'collation_refresh: % database(s) still stale', (select count(*) from stale);
  end if;
end $$;
