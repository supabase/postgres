{ self, pkgs }:
let
  pname = "safeupdate";
  inherit (pkgs) lib;
  system = pkgs.pkgsLinux.stdenv.hostPlatform.system;
  testLib = import ./lib.nix { inherit self pkgs; };
  installedExtension =
    postgresMajorVersion: self.legacyPackages.${system}."psql_${postgresMajorVersion}".exts."${pname}";
  versions = postgresqlMajorVersion: (installedExtension postgresqlMajorVersion).versions;
  orioledbVersions = self.legacyPackages.${system}."psql_orioledb-17".exts."${pname}".versions;
in
self.inputs.nixpkgs.lib.nixos.runTest {
  name = pname;
  hostPkgs = pkgs;
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

      specialisation.orioledb17.configuration = testLib.makeOrioledbSpecialisation { };
    };
  testScript =
    { nodes, ... }:
    let
      pg17-configuration = "${nodes.server.system.build.toplevel}/specialisation/postgresql17";
      orioledb17-configuration = "${nodes.server.system.build.toplevel}/specialisation/orioledb17";
    in
    ''
      from pathlib import Path
      versions = {
        "15": [${lib.concatStringsSep ", " (map (s: ''"${s}"'') (versions "15"))}],
        "17": [${lib.concatStringsSep ", " (map (s: ''"${s}"'') (versions "17"))}],
        "orioledb-17": [${lib.concatStringsSep ", " (map (s: ''"${s}"'') orioledbVersions)}],
      }
      extension_name = "${pname}"
      support_upgrade = False
      pg17_configuration = "${pg17-configuration}"
      orioledb17_configuration = "${orioledb17-configuration}"
      sql_test_directory = Path("${../../tests}")

      ${builtins.readFile ./lib.py}

      test = PostgresExtensionTest(server, extension_name, versions, sql_test_directory, support_upgrade)

      def setup_test_table():
          """Create a test table for safeupdate behavior tests."""
          test.run_sql("DROP TABLE IF EXISTS _test_safeupdate")
          test.run_sql("CREATE TABLE _test_safeupdate (id int)")
          test.run_sql("INSERT INTO _test_safeupdate VALUES (1)")
          test.run_sql("GRANT ALL ON _test_safeupdate TO postgres")

      def cleanup_test_table():
          test.run_sql("DROP TABLE IF EXISTS _test_safeupdate")

      def check_role_config():
          """Verify session_preload_libraries is set for anon and authenticated roles."""
          anon_config = test.run_sql("SELECT rolconfig FROM pg_roles WHERE rolname = 'anon'")
          assert "session_preload_libraries=safeupdate" in anon_config, (
              f"Expected safeupdate in anon session_preload_libraries, got: {anon_config}"
          )

          auth_config = test.run_sql("SELECT rolconfig FROM pg_roles WHERE rolname = 'authenticated'")
          assert "session_preload_libraries=safeupdate" in auth_config, (
              f"Expected safeupdate in authenticated session_preload_libraries, got: {auth_config}"
          )

      def check_blocks_unsafe_operations():
          """Verify safeupdate blocks UPDATE/DELETE without WHERE when loaded."""
          setup_test_table()

          # UPDATE without WHERE should fail when safeupdate is loaded
          server.fail(
              """psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 -c "LOAD 'safeupdate'" -c "UPDATE _test_safeupdate SET id = 2" """
          )

          # UPDATE with WHERE should succeed
          server.succeed(
              """psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 -c "LOAD 'safeupdate'" -c "UPDATE _test_safeupdate SET id = 2 WHERE id = 1" """
          )

          # DELETE without WHERE should fail when safeupdate is loaded
          server.fail(
              """psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 -c "LOAD 'safeupdate'" -c "DELETE FROM _test_safeupdate" """
          )

          # DELETE with WHERE should succeed
          server.succeed(
              """psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 -c "LOAD 'safeupdate'" -c "DELETE FROM _test_safeupdate WHERE id = 2" """
          )

          cleanup_test_table()

      def check_postgres_not_blocked():
          """Verify postgres is not blocked by default (safeupdate not in their session_preload_libraries)."""
          setup_test_table()

          server.succeed(
              """psql -h 127.0.0.1 -U postgres -d postgres -v ON_ERROR_STOP=1 -c "UPDATE _test_safeupdate SET id = 2" """
          )
          server.succeed(
              """psql -h 127.0.0.1 -U postgres -d postgres -v ON_ERROR_STOP=1 -c "DELETE FROM _test_safeupdate" """
          )

          cleanup_test_table()

      def check_postgres_can_enable():
          """Verify postgres can opt-in to safeupdate for their role."""
          test.run_sql("ALTER ROLE postgres SET session_preload_libraries = 'safeupdate'")

          setup_test_table()

          # Now postgres should be blocked (new session picks up role setting)
          server.fail(
              """psql -h 127.0.0.1 -U postgres -d postgres -v ON_ERROR_STOP=1 -c "UPDATE _test_safeupdate SET id = 2" """
          )

          # Clean up
          test.run_sql("ALTER ROLE postgres RESET session_preload_libraries")
          cleanup_test_table()

      start_all()

      server.wait_for_unit("supabase-db-init.service")

      with subtest("Verify PostgreSQL 15 is our custom build"):
        pg_version = server.succeed(
          "psql -U supabase_admin -d postgres -t -A -c \"SELECT version();\""
        ).strip()
        assert "${testLib.expectedVersions."15"}" in pg_version, (
          f"Expected version ${testLib.expectedVersions."15"}, got: {pg_version}"
        )

      with subtest("Verify ansible config loaded"):
        spl = server.succeed(
          "psql -U supabase_admin -d postgres -t -A -c \"SHOW shared_preload_libraries;\""
        ).strip()
        for ext in ["pg_stat_statements", "pgaudit", "pgsodium", "pg_cron", "pg_net"]:
          assert ext in spl, f"Expected {ext} in shared_preload_libraries, got: {spl}"

        session_pl = server.succeed(
          "psql -U supabase_admin -d postgres -t -A -c \"SHOW session_preload_libraries;\""
        ).strip()
        assert "supautils" in session_pl, (
          f"Expected supautils in session_preload_libraries, got: {session_pl}"
        )

      with subtest("Verify init scripts and migrations ran"):
        roles = server.succeed(
          "psql -U supabase_admin -d postgres -t -A -c \"SELECT rolname FROM pg_roles ORDER BY rolname;\""
        ).strip()
        for role in ["anon", "authenticated", "authenticator", "dashboard_user", "pgbouncer", "service_role", "supabase_admin", "supabase_auth_admin", "supabase_storage_admin"]:
          assert role in roles, f"Expected role {role} to exist, got: {roles}"

      with subtest("Check safeupdate role configuration on PostgreSQL 15"):
          check_role_config()

      with subtest("Check safeupdate blocks unsafe operations on PostgreSQL 15"):
          check_blocks_unsafe_operations()

      with subtest("Check postgres is not blocked by default on PostgreSQL 15"):
          check_postgres_not_blocked()

      with subtest("Check postgres can enable safeupdate on PostgreSQL 15"):
          check_postgres_can_enable()

      with subtest("Switch to PostgreSQL 17"):
          server.succeed(
              f"{pg17_configuration}/bin/switch-to-configuration test >&2"
          )
          server.wait_for_unit("postgresql.service")

      with subtest("Verify PostgreSQL 17 is our custom build"):
        pg_version = server.succeed(
          "psql -U supabase_admin -d postgres -t -A -c \"SELECT version();\""
        ).strip()
        assert "${testLib.expectedVersions."17"}" in pg_version, (
          f"Expected version ${testLib.expectedVersions."17"}, got: {pg_version}"
        )

      with subtest("Check safeupdate role configuration on PostgreSQL 17"):
          check_role_config()

      with subtest("Check safeupdate blocks unsafe operations on PostgreSQL 17"):
          check_blocks_unsafe_operations()

      with subtest("Check postgres is not blocked by default on PostgreSQL 17"):
          check_postgres_not_blocked()

      with subtest("Switch to OrioleDB 17"):
          server.succeed(
              f"{orioledb17_configuration}/bin/switch-to-configuration test >&2"
          )
          server.wait_for_unit("supabase-db-init.service")

      with subtest("Verify OrioleDB is running"):
        installed_extensions = server.succeed(
          "psql -U supabase_admin -d postgres -t -A -c \"SELECT extname FROM pg_extension WHERE extname = 'orioledb';\""
        ).strip()
        assert "orioledb" in installed_extensions, (
          f"Expected orioledb extension to be installed, got: {installed_extensions}"
        )

      with subtest("Check safeupdate role configuration on OrioleDB 17"):
          check_role_config()

      with subtest("Check safeupdate blocks unsafe operations on OrioleDB 17"):
          check_blocks_unsafe_operations()

      with subtest("Check postgres is not blocked by default on OrioleDB 17"):
          check_postgres_not_blocked()
    '';
}
