-- Grant EXECUTE on amcheck's functions to the postgres role.
--
-- amcheck is pinned to pg_catalog. supautils creates it as supabase_admin, and neither
-- pg_catalog's default privileges nor amcheck's own SQL (REVOKE ALL FROM PUBLIC) grant the
-- customer anything, so without this the non-superuser postgres role cannot call
-- bt_index_check(). Only postgres is granted; the API roles (anon, authenticated,
-- service_role) are never granted, so amcheck stays off the REST surface. Granting
-- explicitly here (rather than via a schema's default privileges) keeps amcheck's object
-- privileges centrally managed in this repo. See PSQL-1327.
--
-- KNOWN LIMITATION: this runs only at CREATE. supautils has no after-update hook, so
-- functions added by ALTER EXTENSION amcheck UPDATE (amcheck 1.3 -> 1.4 during a 15 -> 17
-- pg_upgrade) are NOT granted to postgres. Accepted for now and tracked as a post-incident
-- follow-up (e.g. an after-update hook in supautils, or disallowing extension-version
-- selection so no in-place update is needed). The amcheck-upgrade VM test documents this.
do $$
declare
  saved_search_path text := (select current_setting('search_path'));
  r record;
begin
  perform set_config('search_path', '', true);

  for r in
    select p.oid::regprocedure as sig
      from pg_depend d
      join pg_proc p on p.oid = d.objid and d.classid = 'pg_proc'::regclass
      join pg_extension e on e.oid = d.refobjid
     where e.extname = 'amcheck' and d.deptype = 'e'
  loop
    execute format('grant execute on function %s to postgres', r.sig);
  end loop;

  perform set_config('search_path', saved_search_path, true);
end $$;
