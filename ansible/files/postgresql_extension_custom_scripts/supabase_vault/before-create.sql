do $$
declare
  saved_search_path pg_catalog.text := (select pg_catalog.current_setting('search_path'));
  _extversion pg_catalog.text := @extversion@;
begin
  perform pg_catalog.set_config('search_path', 'pg_catalog, pg_temp', true);

  if _extversion is not null
  and _extversion OPERATOR(pg_catalog.=) '0.2.8'
  and exists (
    select from pg_available_extension_versions
    where name OPERATOR(pg_catalog.=) 'supabase_vault'
    and version OPERATOR(pg_catalog.<>) '0.2.8'
  )
  then
    raise exception 'Vault 0.2.8 is unsupported';
  end if;

  perform pg_catalog.set_config('search_path', saved_search_path, true);
end $$;
