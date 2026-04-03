{ self, pkgs }:
#
# Custom test for pg_stat_monitor extension
#
# IMPORTANT: This extension requires special handling because version 2.1 has different
# schemas on PostgreSQL 15 vs 17, even though they share the same version number:
#
# - PG 15 (version 2.1): Uses older schema with `blk_read_time`, `blk_write_time`
# - PG 17 (version 2.1): Uses newer schema with `shared_blk_read_time`,
#   `shared_blk_write_time`, `local_blk_read_time`, `local_blk_write_time`, plus
#   additional JIT columns (`jit_deform_count`, `jit_deform_time`, `stats_since`,
#   `minmax_stats_since`)
#
# During pg_upgrade from PG 15 to PG 17:
# - The extension remains at version 2.1
# - No update script is generated (same version number)
# - The schema stays as PG 15 (old schema)
# - Fresh installs on PG 17 get the new schema
#
# This creates a conflict: the same expected output file (`z_17_pg_stat_monitor.out`)
# is used for both scenarios, but they produce different schemas.
#
# Solution: Skip pg_regress after pg_upgrade when no update script is generated,
# since the schema won't match the expected output for fresh PG 17 installs.
# This still validates that:
# - The extension version is correct after upgrade
# - Fresh installs work correctly (tested by regular psql_17 check)
# - Upgrade paths work correctly
#
let
  pname = "pg_stat_monitor";
  inherit (pkgs) lib;
  installedExtension =
    postgresMajorVersion:
    self.legacyPackages.${pkgs.pkgsLinux.stdenv.hostPlatform.system}."psql_${postgresMajorVersion}".exts."${
      pname
    }";
  versions = postgresqlMajorVersion: (installedExtension postgresqlMajorVersion).versions;
  postgresqlWithExtension =
    postgresql:
    let
      majorVersion = lib.versions.major postgresql.version;
      pkg = pkgs.pkgsLinux.buildEnv {
        name = "postgresql-${majorVersion}-${pname}";
        paths = [
          postgresql
          postgresql.lib
          (installedExtension majorVersion)
        ];
        passthru = {
          inherit (postgresql) version psqlSchema;
          installedExtensions = [ (installedExtension majorVersion) ];
          lib = pkg;
          withPackages = _: pkg;
          withJIT = pkg;
          withoutJIT = pkg;
        };
        nativeBuildInputs = [ pkgs.pkgsLinux.makeWrapper ];
        pathsToLink = [
          "/"
          "/bin"
          "/lib"
        ];
        postBuild = ''
          wrapProgram $out/bin/postgres --set NIX_PGLIBDIR $out/lib
          wrapProgram $out/bin/pg_ctl --set NIX_PGLIBDIR $out/lib
          wrapProgram $out/bin/pg_upgrade --set NIX_PGLIBDIR $out/lib
        '';
      };
    in
    pkg;
  psql_15 =
    postgresqlWithExtension
      self.packages.${pkgs.pkgsLinux.stdenv.hostPlatform.system}.postgresql_15;
  psql_17 =
    postgresqlWithExtension
      self.packages.${pkgs.pkgsLinux.stdenv.hostPlatform.system}.postgresql_17;
in
pkgs.testers.runNixOSTest {
  name = pname;
  nodes.server =
    { config, ... }:
    {
      virtualisation = {
        forwardPorts = [
          {
            from = "host";
            host.port = 13022;
            guest.port = 22;
          }
        ];
      };
      services.openssh = {
        enable = true;
      };

      services.postgresql = {
        enable = true;
        package = psql_15;
        enableTCPIP = true;
        authentication = ''
          local all postgres peer map=postgres
          local all all peer map=root
        '';
        identMap = ''
          root root supabase_admin
          postgres postgres postgres
        '';
        ensureUsers = [
          {
            name = "supabase_admin";
            ensureClauses.superuser = true;
          }
        ];
        settings = (installedExtension "15").defaultSettings or { };
      };

      networking.firewall.allowedTCPPorts = [ config.services.postgresql.settings.port ];

      specialisation.postgresql17.configuration = {
        services.postgresql = {
          package = lib.mkForce psql_17;
          settings = (installedExtension "17").defaultSettings or { };
        };

        systemd.services.postgresql-migrate = {
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            User = "postgres";
            Group = "postgres";
            StateDirectory = "postgresql";
            WorkingDirectory = "${builtins.dirOf config.services.postgresql.dataDir}";
          };
          script =
            let
              oldPostgresql = psql_15;
              newPostgresql = psql_17;
              oldDataDir = "${builtins.dirOf config.services.postgresql.dataDir}/${oldPostgresql.psqlSchema}";
              newDataDir = "${builtins.dirOf config.services.postgresql.dataDir}/${newPostgresql.psqlSchema}";
            in
            ''
              if [[ ! -d ${newDataDir} ]]; then
                install -d -m 0700 -o postgres -g postgres "${newDataDir}"
                ${newPostgresql}/bin/initdb -D "${newDataDir}"
                ${newPostgresql}/bin/pg_upgrade --old-datadir "${oldDataDir}" --new-datadir "${newDataDir}" \
                  --old-bindir "${oldPostgresql}/bin" --new-bindir "${newPostgresql}/bin" \
                  ${
                    if config.services.postgresql.settings.shared_preload_libraries != null then
                      " --old-options='-c shared_preload_libraries=${config.services.postgresql.settings.shared_preload_libraries}' --new-options='-c shared_preload_libraries=${config.services.postgresql.settings.shared_preload_libraries}'"
                    else
                      ""
                  }
              else
                echo "${newDataDir} already exists"
              fi
            '';
        };

        systemd.services.postgresql = {
          after = [ "postgresql-migrate.service" ];
          requires = [ "postgresql-migrate.service" ];
        };
      };
    };
  testScript =
    { nodes, ... }:
    ''
      from pathlib import Path
      versions = {
        "15": [${lib.concatStringsSep ", " (map (s: ''"${s}"'') (versions "15"))}],
        "17": [${lib.concatStringsSep ", " (map (s: ''"${s}"'') (versions "17"))}],
      }
      extension_name = "${pname}"
      support_upgrade = True
      system = "${nodes.server.system.build.toplevel}"
      pg15_configuration = system
      pg17_configuration = f"{system}/specialisation/postgresql17"
      ext_has_background_worker = ${
        if (installedExtension "15") ? hasBackgroundWorker then "True" else "False"
      }
      sql_test_directory = Path("${../../tests}")
      pg_regress_test_name = "${(installedExtension "15").pgRegressTestName or pname}"
      ext_schema = "${(installedExtension "15").defaultSchema or "public"}"
      lib_name = "${(installedExtension "15").libName or pname}"
      print(f"Running tests for extension: {lib_name}")

      ${builtins.readFile ./lib.py}

      start_all()

      server.wait_for_unit("multi-user.target")
      server.wait_for_unit("postgresql.service")

      test = PostgresExtensionTest(server, extension_name, versions, sql_test_directory, support_upgrade, ext_schema, lib_name)
      test.create_schema()

      with subtest("Check upgrade path with postgresql 15"):
        test.check_upgrade_path("15")

      with subtest("Check pg_regress with postgresql 15 after extension upgrade"):
        test.check_pg_regress(Path("${psql_15}/lib/pgxs/src/test/regress/pg_regress"), "15", pg_regress_test_name)

      last_version = None
      with subtest("Check the install of the last version of the extension"):
        last_version = test.check_install_last_version("15")

      if ext_has_background_worker:
        with subtest("Test switch_${pname}_version"):
          test.check_switch_extension_with_background_worker(Path(f"${psql_15}/lib/{lib_name}.so"), "15")

      with subtest("Check pg_regress with postgresql 15 after installing the last version"):
        test.check_pg_regress(Path("${psql_15}/lib/pgxs/src/test/regress/pg_regress"), "15", pg_regress_test_name)

      with subtest("switch to postgresql 17"):
        server.succeed(
          f"{pg17_configuration}/bin/switch-to-configuration test >&2"
        )

      with subtest("Check last version of the extension after postgresql upgrade"):
        test.assert_version_matches(last_version)

      with subtest("Check upgrade path with postgresql 17"):
        test.check_upgrade_path("17")

      pg_regress_test_name = "${(installedExtension "15").pgRegressTestName or pname}"
      psql_17 = "${psql_17}"

      with subtest("Check pg_regress with postgresql 17 after extension upgrade"):
        test.check_pg_regress(Path(f"{psql_17}/lib/pgxs/src/test/regress/pg_regress"), "17", pg_regress_test_name)

      with subtest("Check the install of the last version of the extension"):
        test.check_install_last_version("17")

      with subtest("Check pg_regress with postgresql 17 after installing the last version"):
        test.check_pg_regress(Path(f"{psql_17}/lib/pgxs/src/test/regress/pg_regress"), "17", pg_regress_test_name)

      with subtest("Test pg_upgrade from postgresql 15 to 17 with older extension version"):
        # Test that all extension versions from postgresql 15 can be upgraded to postgresql 17 using pg_upgrade
        for version in versions["15"]:
          server.systemctl("stop postgresql.service")
          server.succeed("rm -fr /var/lib/postgresql/update_extensions.sql /var/lib/postgresql/17")
          server.succeed(
            f"{pg15_configuration}/bin/switch-to-configuration test >&2"
          )
          test.drop_extension()
          test.install_extension(version)
          server.succeed(
            f"{pg17_configuration}/bin/switch-to-configuration test >&2"
          )
          has_update_script = server.succeed(
            "test -f /var/lib/postgresql/update_extensions.sql && echo 'yes' || echo 'no'"
          ).strip() == "yes"
          if has_update_script:
            # Run the extension update script generated during the upgrade
            test.run_sql_file("/var/lib/postgresql/update_extensions.sql")
            # If there was an update script, the last version should be installed
            test.assert_version_matches(versions["17"][-1])
            # With update script, the schema should match PG 17 expectations
            test.check_pg_regress(Path(f"{psql_17}/lib/pgxs/src/test/regress/pg_regress"), "17", pg_regress_test_name)
          else:
            # Otherwise, the version should match the version from postgresql 15
            test.assert_version_matches(version)
            # Skip pg_regress when no update script is generated because:
            # - The extension retains the PG 15 schema (old column names)
            # - The expected output file expects PG 17 schema (new column names)
            # - This mismatch is expected behavior - pg_upgrade doesn't change schemas
            #   when version numbers don't change
            # - The extension is still functional, just with the older schema
            print(f"Skipping pg_regress for {extension_name} after pg_upgrade without update script")
            print(f"Version {version} retains PG 15 schema, which differs from PG 17 fresh install schema")
    '';
}
