{ self, pkgs }:
let
  pname = "pgroonga";
  inherit (pkgs) lib;
  system = pkgs.pkgsLinux.stdenv.hostPlatform.system;
  testLib = import ./lib.nix { inherit self pkgs; };

  installedExtension =
    postgresMajorVersion: self.legacyPackages.${system}."psql_${postgresMajorVersion}".exts."${pname}";
  versions = postgresqlMajorVersion: (installedExtension postgresqlMajorVersion).versions;
  orioledbVersions = self.legacyPackages.${system}."psql_orioledb-17".exts."${pname}".versions;
in
pkgs.testers.runNixOSTest {
  name = pname;
  nodes.server =
    { ... }:
    {
      imports = [
        (testLib.makeSupabaseTestConfig {
          majorVersion = "15";
        })
      ];

      # pgroonga needs mecab environment variables
      systemd.services.postgresql.environment.MECAB_DICDIR = "${
        self.packages.${system}.mecab-naist-jdic
      }/lib/mecab/dic/naist-jdic";
      systemd.services.postgresql.environment.MECAB_CONFIG = "${pkgs.pkgsLinux.mecab}/bin/mecab-config";

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
      support_upgrade = True
      pg17_configuration = "${pg17-configuration}"
      orioledb17_configuration = "${orioledb17-configuration}"
      sql_test_directory = Path("${../../tests}")

      ${builtins.readFile ./lib.py}

      start_all()

      # Wait for full Supabase initialization (postgres + init-scripts + migrations)
      server.wait_for_unit("supabase-db-init.service")

      with subtest("Verify PostgreSQL 15 is our custom build"):
        pg_version = server.succeed(
          "psql -U supabase_admin -d postgres -t -A -c \"SELECT version();\""
        ).strip()
        assert "${testLib.expectedVersions."15"}" in pg_version, (
          f"Expected version ${testLib.expectedVersions."15"}, got: {pg_version}"
        )

        postgres_path = server.succeed("readlink -f $(which postgres)").strip()
        assert "postgresql-and-plugins-${testLib.expectedVersions."15"}" in postgres_path, (
          f"Expected our custom build (${testLib.expectedVersions."15"}), got: {postgres_path}"
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

        schemas = server.succeed(
          "psql -U supabase_admin -d postgres -t -A -c \"SELECT schema_name FROM information_schema.schemata ORDER BY schema_name;\""
        ).strip()
        for schema in ["auth", "storage", "extensions"]:
          assert schema in schemas, f"Expected schema {schema} to exist, got: {schemas}"

      test = PostgresExtensionTest(server, extension_name, versions, sql_test_directory, support_upgrade)

      def pgrn_bytes():
        return int(server.succeed(
          "find /var/lib/postgresql/data/base -name 'pgrn*' -printf '%s\\n' | awk '{s+=$1} END {print s+0}'"
        ).strip())

      def sql(query):
        return server.succeed(f"psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 -t -A -c \"{query}\"").strip()

      def setup_indexed_table():
        sql("CREATE EXTENSION IF NOT EXISTS pgroonga WITH SCHEMA extensions")
        sql("CREATE SCHEMA IF NOT EXISTS repro")
        sql("CREATE TABLE repro.t AS SELECT g AS id, md5(g::text) || ' ' || md5((g * 7)::text) AS body FROM generate_series(1, 20000) g")
        sql("CREATE INDEX repro_idx ON repro.t USING pgroonga (body)")
        sql("SELECT count(*) FROM repro.t WHERE body &@~ 'abc'")

      with subtest("Repro orphaned pgrn files"):
        sql("DROP EXTENSION IF EXISTS pgroonga CASCADE")
        sql("DROP SCHEMA IF EXISTS repro CASCADE")
        baseline = pgrn_bytes()
        print(f"REPRO baseline: {baseline}")

        scenarios = {
          "drop_index_then_drop_extension": ["DROP INDEX repro.repro_idx", "DROP EXTENSION pgroonga"],
          "drop_table": ["DROP TABLE repro.t", "DROP EXTENSION pgroonga"],
          "drop_schema_cascade": ["DROP SCHEMA repro CASCADE", "DROP EXTENSION pgroonga"],
          "drop_extension_cascade": ["DROP EXTENSION pgroonga CASCADE"],
        }
        for name, statements in scenarios.items():
          sql("DROP EXTENSION IF EXISTS pgroonga CASCADE")
          sql("DROP SCHEMA IF EXISTS repro CASCADE")
          setup_indexed_table()
          populated = pgrn_bytes()
          for statement in statements:
            sql(statement)
          sql("DROP SCHEMA IF EXISTS repro CASCADE")
          left = pgrn_bytes()
          print(f"REPRO {name}: baseline={baseline} populated={populated} after_drop={left}")

        with subtest("Dropped index data is kept until a pgroonga index is vacuumed"):
          sql("DROP EXTENSION IF EXISTS pgroonga CASCADE")
          sql("DROP SCHEMA IF EXISTS repro CASCADE")
          setup_indexed_table()
          sql("DROP INDEX repro.repro_idx")
          leaked = pgrn_bytes()
          sql("CREATE TABLE repro.tiny (body text)")
          sql("CREATE INDEX tiny_idx ON repro.tiny USING pgroonga (body)")
          sql("VACUUM repro.tiny")
          vacuumed = pgrn_bytes()
          print(f"REPRO vacuum: leaked={leaked} vacuumed={vacuumed}")
          assert vacuumed < leaked, f"Expected VACUUM on a pgroonga index to remove dropped index data, got {leaked} -> {vacuumed}"
          sql("DROP SCHEMA repro CASCADE")

      with subtest("Check upgrade path with postgresql 15"):
        test.check_upgrade_path("15")

      last_version = None
      with subtest("Check the install of the last version of the extension"):
        last_version = test.check_install_last_version("15")

      with subtest("switch to postgresql 17"):
        server.execute(
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

        postgres_pid = server.succeed(
          "head -1 /var/lib/postgresql/data-17/postmaster.pid"
        ).strip()
        postgres_path = server.succeed(
          f"readlink -f /proc/{postgres_pid}/exe"
        ).strip()
        assert "postgresql-and-plugins-${testLib.expectedVersions."17"}" in postgres_path, (
          f"Expected our custom build (${testLib.expectedVersions."17"}), got: {postgres_path}"
        )

      with subtest("Check last version of the extension after upgrade"):
        test.assert_version_matches(last_version)

      with subtest("Check upgrade path with postgresql 17"):
        test.check_upgrade_path("17")

      with subtest("switch to orioledb 17"):
        server.execute(
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

        dam = server.succeed(
          "psql -U supabase_admin -d postgres -t -A -c \"SHOW default_table_access_method;\""
        ).strip()
        assert dam == "orioledb", (
          f"Expected default_table_access_method = orioledb, got: {dam}"
        )

      with subtest("Verify OrioleDB init scripts and migrations ran"):
        roles = server.succeed(
          "psql -U supabase_admin -d postgres -t -A -c \"SELECT rolname FROM pg_roles ORDER BY rolname;\""
        ).strip()
        for role in ["anon", "authenticated", "authenticator", "supabase_admin"]:
          assert role in roles, f"Expected role {role} to exist, got: {roles}"

      with subtest("Check upgrade path with orioledb 17"):
        test.check_upgrade_path("orioledb-17")
    '';
}
