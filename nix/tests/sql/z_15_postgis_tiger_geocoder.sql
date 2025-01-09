/*
This extension is excluded from oriole-17 because it uses an unsupported index type
*/
create extension if not exists postgis_tiger_geocoder;

select
  name
from 
  pg_available_extensions
where
  installed_version is null
  and name in (
    'postgis_tiger_geocoder'
  )
order by
  name asc;


select
  extname as extension_name,
  extrelocatable as is_relocatable
from
  pg_extension
where
  e.extname in (
    'postgis_tiger_geocoder'
  )
order by
  extname asc;


select
  e.extname as extension_name,
  n.nspname as schema_name,
  p.proname as function_name,
  pg_catalog.pg_get_function_identity_arguments(p.oid) as argument_types,
  pg_catalog.pg_get_function_result(p.oid) as return_type
from
  pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n
    on n.oid = p.pronamespace
  join pg_catalog.pg_depend d
    on d.objid = p.oid
  join pg_catalog.pg_extension e
    on e.oid = d.refobjid
where
  d.deptype = 'e'
  and e.extname in (
    'postgis_tiger_geocoder'
  )
order by
  e.extname,
  n.nspname,
  p.proname,
  pg_catalog.pg_get_function_identity_arguments(p.oid);

select
  e.extname as extension_name,
  n.nspname as schema_name,
  pc.relname as entity_name,
  pa.attname
from
  pg_catalog.pg_class pc
  join pg_catalog.pg_namespace n
    on n.oid = pc.relnamespace
  join pg_catalog.pg_depend d
    on d.objid = pc.oid
  join pg_catalog.pg_extension e
    on e.oid = d.refobjid
  left join pg_catalog.pg_attribute pa
    on pa.attrelid = pc.oid
    and pa.attnum > 0
    and not pa.attisdropped
where
  d.deptype = 'e'
  and pc.relkind in ('r', 'v', 'm', 'i')
  and e.extname in (
    'postgis_tiger_geocoder'
  )
order by
  e.extname,
  n.nspname,
  pc.relname,
  pa.attname;
