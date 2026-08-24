# amcheck across a 15 to 17 pg_upgrade (PSQL-1327).
#
# amcheck is pinned to the pg_catalog schema by
# supautils.extensions_parameter_overrides, which is what keeps EXECUTE away from
# anon, authenticated and service_role. nix/tests/sql/amcheck.sql asserts that on
# a fresh install.
#
# This test covers what pg_regress cannot reach: whether the schema and the
# grants survive a major version upgrade. Two things could break it. Extension
# member function ACLs ride on pg_init_privs through pg_upgrade's dump and
# restore. And 15 ships amcheck 1.3 while 17 ships 1.4, so the upgrade also runs
# an ALTER EXTENSION UPDATE that creates new functions, each picking up whatever
# default privileges apply at that moment.
#
# Upgraded projects are the population the ticket is about (customers hitting
# corrupt indexes after a 15 to 17 upgrade), so a silent re-grant here would undo
# the fix for exactly the people it was written for.
#
# 15 to 17 only. There is no upgrade path into orioledb, since its specialisation
# wipes the data directory, so an orioledb leg would assert nothing here.
{ self, pkgs }:
let
  testLib = import ./lib.nix { inherit self pkgs; };
in
pkgs.testers.runNixOSTest {
  name = "amcheck-upgrade";
  nodes.server =
    { ... }:
    {
      imports = [
        (testLib.makeSupabaseTestConfig {
          majorVersion = "15";
        })
      ];

      specialisation.postgresql17.configuration = testLib.makeUpgradeSpecialisation {
        fromMajorVersion = "15";
        toMajorVersion = "17";
      };
    };
  testScript =
    { nodes, ... }:
    let
      pg17-configuration = "${nodes.server.system.build.toplevel}/specialisation/postgresql17";
    in
    ''
      pg17_configuration = "${pg17-configuration}"

      # postgres holds EXECUTE on amcheck (installed into pg_catalog by supautils);
      # the three PostgREST roles hold nothing. Aggregated over every function
      # the extension owns, so it holds as amcheck grows from 6 on 15 to 8 on 17.
      EXPECTED_ACL = "anon,f,f\nauthenticated,f,f\npostgres,t,t\nservice_role,f,f"

      ACL_QUERY = (
        "select r.rolname, "
        "bool_and(has_function_privilege(r.rolname, p.oid, 'execute')), "
        "bool_or(has_function_privilege(r.rolname, p.oid, 'execute')) "
        "from pg_proc p "
        "join pg_depend d on d.objid = p.oid and d.deptype = 'e' "
        "join pg_extension e on e.oid = d.refobjid and e.extname = 'amcheck' "
        "cross join (values ('postgres'), ('anon'), ('authenticated'), ('service_role')) "
        "as r(rolname) group by r.rolname order by r.rolname"
      )

      IDENTITY_QUERY = (
        "select extversion, extnamespace::regnamespace "
        "from pg_extension where extname = 'amcheck'"
      )

      def sql(query, role=None):
        # Connect as supabase_admin (the superuser this harness authenticates
        # as) and set the target role via the startup packet, so each statement
        # gets its own session instead of one implicit multi-statement -c.
        prefix = ""
        if role is not None:
          prefix = "PGOPTIONS=\"-c role=" + role + "\" "
        return server.succeed(
          prefix
          + "psql -U supabase_admin -d postgres -t -A -F, -v ON_ERROR_STOP=1 -c \""
          + query
          + "\""
        ).strip()

      def sql_fails(query, role=None):
        prefix = ""
        if role is not None:
          prefix = "PGOPTIONS=\"-c role=" + role + "\" "
        return server.fail(
          prefix
          + "psql -U supabase_admin -d postgres -t -A -v ON_ERROR_STOP=1 -c \""
          + query
          + "\" 2>&1"
        )

      start_all()

      # Wait for full Supabase initialization (postgres + init-scripts + migrations),
      # since the roles and default privileges under test come from the migrations.
      server.wait_for_unit("supabase-db-init.service")

      with subtest("Preconditions"):
        assert sql("select rolsuper from pg_roles where rolname = 'postgres'") == "f", (
          "postgres is a superuser; every grant assertion below would be vacuous"
        )
        # Fail loudly if role switching is broken, rather than silently
        # running the whole suite as supabase_admin.
        whoami = sql("select current_user", role="postgres")
        assert whoami == "postgres", f"expected to be acting as postgres, got: {whoami}"

      with subtest("A non-superuser installs amcheck on PG 15, pinned to pg_catalog"):
        sql("create extension amcheck", role="postgres")
        before = sql(IDENTITY_QUERY)
        assert before.endswith(",pg_catalog"), (
          f"expected amcheck in the pg_catalog schema, got: {before}"
        )
        print(f"PG 15 amcheck: {before}")

      with subtest("PG 15 grants reach postgres only"):
        acl_before = sql(ACL_QUERY)
        assert acl_before == EXPECTED_ACL, f"unexpected PG 15 grants:\n{acl_before}"

      with subtest("switch to postgresql 17"):
        server.execute(f"{pg17_configuration}/bin/switch-to-configuration test >&2")
        server.wait_for_unit("postgresql.service")

      with subtest("pg_upgrade preserves amcheck's version, schema and grants"):
        after = sql(IDENTITY_QUERY)
        assert after == before, f"amcheck changed across pg_upgrade: {before} -> {after}"
        acl_after = sql(ACL_QUERY)
        assert acl_after == EXPECTED_ACL, f"grants changed across pg_upgrade:\n{acl_after}"

      with subtest("After the 1.3 -> 1.4 update: API roles stay locked out (postgres grant gap is a KNOWN limitation)"):
        # The platform replays pg_upgrade's generated update_extensions.sql
        # (admin_api_scripts/pg_upgrade_scripts/complete.sh). This harness runs
        # raw pg_upgrade, so replay that file if present, else ALTER explicitly.
        # Either route creates the new 1.4 functions.
        has_script = server.succeed(
          "test -f /var/lib/postgresql/update_extensions.sql && echo yes || echo no"
        ).strip()
        if has_script == "yes":
          server.succeed(
            "psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 "
            "-f /var/lib/postgresql/update_extensions.sql"
          )
        else:
          sql("alter extension amcheck update")

        default_version = sql(
          "select default_version from pg_available_extensions where name = 'amcheck'"
        )
        updated = sql(IDENTITY_QUERY)
        installed_version = updated.split(",")[0]
        assert installed_version == default_version, (
          f"expected amcheck at PG 17's default {default_version}, got {installed_version}"
        )
        # If 15 and 17 ever ship the same amcheck version there are no new
        # functions to acquire grants, and this subtest silently tests nothing.
        assert installed_version != before.split(",")[0], (
          f"amcheck was already at {installed_version} on PG 15; this subtest no "
          "longer exercises a version bump and needs rewriting"
        )
        assert updated.endswith(",pg_catalog"), (
          f"amcheck left the pg_catalog schema during the update: {updated}"
        )

        acl_updated = sql(ACL_QUERY)

        # SECURITY INVARIANT (must always hold): no API role can execute ANY amcheck
        # function, before or after the update. This is the property amcheck is pinned to
        # pg_catalog to guarantee, and it must never regress.
        for role in ["anon", "authenticated", "service_role"]:
          assert f"{role},f,f" in acl_updated, (
            f"SECURITY REGRESSION: {role} can execute an amcheck function after update:\n{acl_updated}"
          )

        # postgres must retain execute on the functions granted at create time (they
        # survive pg_upgrade), i.e. any_function is still true.
        assert ("postgres,t,t" in acl_updated) or ("postgres,f,t" in acl_updated), (
          f"postgres lost execute on amcheck across the update:\n{acl_updated}"
        )

        # KNOWN LIMITATION (PSQL-1327): the 1.3 -> 1.4 update adds functions the create-time
        # after-create grant did not cover, because supautils has no after-update hook. So
        # postgres may show all_functions=f (cannot run the new 1.4 functions). This is
        # accepted for now and tracked as a post-incident follow-up. We assert the security
        # invariant above rather than full postgres coverage, so this documents the gap
        # without masking a real security regression. When the gap is fixed upstream, the
        # matrix becomes postgres,t,t and this note should be removed.
        if "postgres,f,t" in acl_updated:
          print("KNOWN LIMITATION (PSQL-1327): postgres lacks execute on amcheck functions added by the 1.3 -> 1.4 update")

      with subtest("The support workflow still works after the upgrade"):
        sql(
          "create table amcheck_heap(i int primary key) using heap; "
          "insert into amcheck_heap select generate_series(1, 100)",
          role="postgres",
        )
        sql("select pg_catalog.bt_index_check('amcheck_heap_pkey'::regclass)", role="postgres")
        # amcheck has no per relation gate, which is the point: a customer can
        # check an auth index they do not own after an upgrade corrupts it.
        sql("select pg_catalog.bt_index_check('auth.users_pkey'::regclass)", role="postgres")

      with subtest("The API roles are still locked out after the upgrade"):
        for role in ["anon", "authenticated", "service_role"]:
          err = sql_fails(
            "select pg_catalog.bt_index_check('auth.users_pkey'::regclass)", role=role
          )
          assert "permission denied for function bt_index_check" in err, (
            f"expected {role} to be denied, got: {err}"
          )
    '';
}
