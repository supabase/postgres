do $$
declare
  -- It's important that the declare section doesn't have any initialization code.
  -- Any initialization should happen in the begin/end block after search_path is
  -- set to avoid search_path hijacking attacks.
  search_path text;
  r record;
begin
  -- Instead of setting search_path to an empty string we set it to an explicit list
  -- of pg_catalog and pg_temp. With an empty string, pg_temp is implicitly added as the
  -- first entry in search_path by Postgres. Although having pg_temp first in search_path
  -- is not always exploitable (because it's only used to lookup tables, views etc. and
  -- not functions, or procedures) it's a defence is depth measure to guard against
  -- potential later changes in the code accidentally creating a vulnerability.
  search_path := current_setting('search_path');
  perform set_config('search_path', 'pg_catalog, pg_temp', true);

  for r in (select oid, (aclexplode(proacl)).grantee from pg_proc where proname = 'dblink_connect_u') loop
   continue when r.grantee = 'supabase_admin'::regrole;
   execute(
     format(
       'revoke all on function %s(%s) from %s;', r.oid::regproc, pg_get_function_identity_arguments(r.oid), r.grantee::regrole
     )
   );
  end loop;

  -- restore search_path to its previous value
  perform set_config('search_path', search_path, true);
end
$$;
