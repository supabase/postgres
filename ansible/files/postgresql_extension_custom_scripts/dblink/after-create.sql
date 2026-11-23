do $$
declare
  saved_search_path pg_catalog.text := (select pg_catalog.current_setting('search_path'));
  r pg_catalog.record;
begin
  perform pg_catalog.set_config('search_path', 'pg_catalog, pg_temp', true);

  for r in (select oid, (aclexplode(proacl)).grantee from pg_proc where proname = 'dblink_connect_u') loop
   continue when r.grantee = 'supabase_admin'::regrole;
   execute(
     format(
       'revoke all on function %s(%s) from %s;', r.oid::regproc, pg_get_function_identity_arguments(r.oid), r.grantee::regrole
     )
   );
  end loop;

  perform pg_catalog.set_config('search_path', saved_search_path, true);
end $$;
