# amcheck across a 15 -> 17 pg_upgrade (PSQL-1327).
#
# amcheck is a customer-installable privileged extension pinned to the
# `extensions` schema by supautils.extensions_parameter_overrides. That pin is
# what keeps EXECUTE away from anon/authenticated/service_role: in `public` the
# ALTER DEFAULT PRIVILEGES in initial-schema.sql would grant to all four roles,
# and amcheck performs no permission check of its own, so a grant is a licence
# to check any index in the database.
#
# nix/tests/sql/amcheck.sql asserts that on a fresh install. This test covers
# the part pg_regress cannot reach: whether the schema and the grants survive a
# major-version upgrade. That matters because extension-member function ACLs
# ride on pg_init_privs through pg_upgrade's dump/restore, and because 15 ships
# amcheck 1.3 while 17 ships 1.4 -- so the upgrade also runs an ALTER EXTENSION
# UPDATE that creates new functions, each of which picks up whatever default
# privileges apply at that moment.
#
# Upgraded projects are exactly the population the ticket is about (customers
# hitting corrupt indexes after 15 -> 17), so a silent re-grant here would undo
# the fix for everyone who matters.
#
# Deliberately 15 -> 17 only. There is no upgrade path into orioledb (its
# specialisation wipes the data directory), so an orioledb leg would assert
# nothing about upgrade behaviour and only add VM runtime.
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

      # postgres holds EXECUTE (with grant option, via the extensions-schema
      # default privileges); the three PostgREST roles hold nothing. Aggregated
      # over every function the extension owns rather than named signatures, so
      # this stays correct as amcheck grows from 6 functions on 15 to 8 on 17.
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
        # Connect as supabase_admin (the bootstrap superuser this harness
        # authenticates as) and pick up the target role via the startup packet,
        # so each statement runs under its own session rather than being bundled
        # into one implicit transaction by a multi-statement -c.
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
        # Fail loudly if the role-switching mechanism itself is broken, rather
        # than silently running the whole suite as supabase_admin.
        whoami = sql("select current_user", role="postgres")
        assert whoami == "postgres", f"expected to be acting as postgres, got: {whoami}"

      with subtest("A non-superuser installs amcheck on PG 15, pinned to extensions"):
        sql("create extension amcheck", role="postgres")
        before = sql(IDENTITY_QUERY)
        assert before.endswith(",extensions"), (
          f"expected amcheck in the extensions schema, got: {before}"
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

      with subtest("The 1.3 -> 1.4 extension update preserves the grants"):
        # The platform runs pg_upgrade's generated update_extensions.sql after
        # the upgrade (admin_api_scripts/pg_upgrade_scripts/complete.sh). This
        # harness runs raw pg_upgrade, so replay that file when it is present
        # and fall back to an explicit ALTER when it is not -- either route
        # creates the new 1.4 functions, which is what we need to inspect.
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
        # Guard against this subtest quietly becoming a no-op if 15 and 17 ever
        # ship the same amcheck version -- there would then be no new functions
        # to acquire grants, and nothing here would be under test.
        assert installed_version != before.split(",")[0], (
          f"amcheck was already at {installed_version} on PG 15; this subtest no "
          "longer exercises a version bump and needs rewriting"
        )
        assert updated.endswith(",extensions"), (
          f"amcheck left the extensions schema during the update: {updated}"
        )

        acl_updated = sql(ACL_QUERY)
        assert acl_updated == EXPECTED_ACL, (
          f"grants changed when amcheck was updated to {installed_version}:\n{acl_updated}"
        )

      with subtest("The support workflow still works after the upgrade"):
        sql(
          "create table amcheck_heap(i int primary key) using heap; "
          "insert into amcheck_heap select generate_series(1, 100)",
          role="postgres",
        )
        sql("select extensions.bt_index_check('amcheck_heap_pkey'::regclass)", role="postgres")
        # amcheck has no per-relation gate, which is the point: a customer can
        # check an auth index they do not own after an upgrade corrupts it.
        sql("select extensions.bt_index_check('auth.users_pkey'::regclass)", role="postgres")

      with subtest("The API roles are still locked out after the upgrade"):
        for role in ["anon", "authenticated", "service_role"]:
          err = sql_fails(
            "select extensions.bt_index_check('auth.users_pkey'::regclass)", role=role
          )
          assert "permission denied for function bt_index_check" in err, (
            f"expected {role} to be denied, got: {err}"
          )
    '';
}
