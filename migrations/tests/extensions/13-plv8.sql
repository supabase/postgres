begin;
do $_$
begin
  if not exists (select 1 from pg_extension where extname = 'orioledb') then
    create extension if not exists plv8 with schema "pg_catalog";
  end if;
end
$_$;
rollback;
