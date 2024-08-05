select
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
    e.extname = 'postgis' -- replace with your extension name
    and n.nspname = 'public'
    and d.deptype = 'e'
order by
    schema_name,
    function_name;
