# Whether amcheck's pg_catalog pin and grants survive a real 15 -> 17
# pg_upgrade, not just a fresh install (see nix/tests/sql/amcheck.sql for that).
# No orioledb leg: its specialisation wipes the data directory, so there is no
# upgrade path into it to test.
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

      # postgres: EXECUTE on all amcheck functions; anon/authenticated/service_role: none.
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
        prefix = "" if role is None else "PGOPTIONS=\"-c role=" + role + "\" "
        return server.succeed(
          prefix
          + "psql -U supabase_admin -d postgres -t -A -F, -v ON_ERROR_STOP=1 -c \""
          + query
          + "\""
        ).strip()

      start_all()
      server.wait_for_unit("supabase-db-init.service")

      with subtest("Preconditions"):
        assert sql("select rolsuper from pg_roles where rolname = 'postgres'") == "f", (
          "postgres is a superuser; every grant assertion below would be vacuous"
        )
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

      with subtest("amcheck updates to PG 17's default version"):
        # Production replays pg_upgrade's generated update_extensions.sql; this
        # harness runs a bare pg_upgrade, so replay it if present, else do the
        # equivalent ALTER directly.
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
        assert installed_version != before.split(",")[0], (
          f"amcheck was already at {installed_version} on PG 15; this test no "
          "longer exercises a version bump and needs rewriting"
        )
        assert updated.endswith(",pg_catalog"), (
          f"amcheck left the pg_catalog schema during the update: {updated}"
        )

        # Must always hold: no API role can execute any amcheck function.
        acl_updated = sql(ACL_QUERY)
        for role in ["anon", "authenticated", "service_role"]:
          assert f"{role},f,f" in acl_updated, (
            f"SECURITY REGRESSION: {role} can execute an amcheck function after update:\n{acl_updated}"
          )

      with subtest("The support workflow still works after the upgrade"):
        sql(
          "create table amcheck_heap(i int primary key) using heap; "
          "insert into amcheck_heap select generate_series(1, 100)",
          role="postgres",
        )
        sql("select pg_catalog.bt_index_check('amcheck_heap_pkey'::regclass)", role="postgres")
        # No per-relation gate: a customer can check an auth index they don't own.
        sql("select pg_catalog.bt_index_check('auth.users_pkey'::regclass)", role="postgres")

      with subtest("PG17-only overload added in amcheck 1.4 is callable by postgres"):
        # Expected to fail: this harness's bare pg_upgrade never runs the
        # drop-before/recreate-after fix that lives in production's initiate.sh.
        sql(
          "select pg_catalog.bt_index_check('amcheck_heap_pkey'::regclass, false, false)",
          role="postgres",
        )
    '';
}
