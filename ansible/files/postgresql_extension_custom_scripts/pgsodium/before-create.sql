do $$
declare
  saved_search_path pg_catalog.text := (select pg_catalog.current_setting('search_path'));
  _extversion pg_catalog.text := @extversion@;
begin
  perform pg_catalog.set_config('search_path', 'pg_catalog, pg_temp', true);

  if _extversion is not null and _extversion OPERATOR(pg_catalog.<>) '3.1.8' then
    raise exception 'only pgsodium 3.1.8 is supported';
  end if;

  perform pg_catalog.set_config('search_path', saved_search_path, true);
end $$;
