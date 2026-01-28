{ self, pkgs }:
let
  pname = "index_advisor";
  inherit (pkgs) lib;
  installedExtension =
    postgresMajorVersion:
    self.legacyPackages.${pkgs.pkgsLinux.stdenv.hostPlatform.system}."psql_${postgresMajorVersion}".exts.index_advisor;
  versions = postgresqlMajorVersion: (installedExtension postgresqlMajorVersion).versions;
  postgresqlWithExtension =
    postgresql:
    let
      majorVersion =
        if postgresql.isOrioleDB then "orioledb-17" else lib.versions.major postgresql.version;
      pkg = pkgs.pkgsLinux.buildEnv {
        name = "postgresql-${majorVersion}-${pname}";
        paths = [
          postgresql
          postgresql.lib
          (installedExtension majorVersion)
        ]
        ++ lib.optional (postgresql.isOrioleDB
        ) self.legacyPackages.${pkgs.pkgsLinux.stdenv.hostPlatform.system}.psql_orioledb-17.exts.orioledb;
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
  orioledb_17 =
    postgresqlWithExtension
      self.packages.${pkgs.pkgsLinux.stdenv.hostPlatform.system}.postgresql_orioledb-17;
in
pkgs.testers.runNixOSTest {
  name = pname;
  nodes.server =
    { config, ... }:
    {
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
                  --old-bindir "${oldPostgresql}/bin" --new-bindir "${newPostgresql}/bin"
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

      specialisation.orioledb17.configuration = {
        services.postgresql = {
          package = lib.mkForce (
            postgresqlWithExtension
              self.packages.${pkgs.pkgsLinux.stdenv.hostPlatform.system}.postgresql_orioledb-17
          );
          settings = lib.mkForce (
            ((installedExtension "17").defaultSettings or { })
            // {
              jit = "off";
              shared_preload_libraries = [
                "orioledb"
              ]
              ++ (lib.toList ((installedExtension "17").defaultSettings.shared_preload_libraries or [ ]));
              default_table_access_method = "orioledb";
            }
          );
          initdbArgs = [
            "--allow-group-access"
            "--locale-provider=icu"
            "--encoding=UTF-8"
            "--icu-locale=en_US.UTF-8"
          ];
          initialScript = pkgs.writeText "init-postgres-with-orioledb" ''
            CREATE EXTENSION orioledb CASCADE;
          '';
        };

        systemd.services.postgresql-migrate = {
          # we don't support migrating from postgresql 17 to orioledb-17 so we just reinit the datadir
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
              newPostgresql =
                postgresqlWithExtension
                  self.packages.${pkgs.pkgsLinux.stdenv.hostPlatform.system}.postgresql_orioledb-17;
            in
            ''
              if [[ -z "${newPostgresql.psqlSchema}" ]]; then
                echo "Error: psqlSchema is empty, refusing to rm -rf"
                exit 1
              fi
              rm -rf ${builtins.dirOf config.services.postgresql.dataDir}/${newPostgresql.psqlSchema}
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
    let
      pg17-configuration = "${nodes.server.system.build.toplevel}/specialisation/postgresql17";
      orioledb17-configuration = "${nodes.server.system.build.toplevel}/specialisation/orioledb17";
    in
    ''
      from pathlib import Path
      versions = {
        "15": [${lib.concatStringsSep ", " (map (s: ''"${s}"'') (versions "15"))}],
        "17": [${lib.concatStringsSep ", " (map (s: ''"${s}"'') (versions "17"))}],
        "orioledb-17": [${lib.concatStringsSep ", " (map (s: ''"${s}"'') (versions "orioledb-17"))}],
      }
      extension_name = "${pname}"
      support_upgrade = True
      ext_has_background_worker = ${
        if (installedExtension "15") ? hasBackgroundWorker then "True" else "False"
      }
      sql_test_directory = Path("${../../tests}")
      pg_regress_test_name = "${(installedExtension "15").pgRegressTestName or pname}"
      ext_schema = "${(installedExtension "15").defaultSchema or "public"}"
      lib_name = "${(installedExtension "15").libName or pname}"

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
          "${pg17-configuration}/bin/switch-to-configuration test >&2"
        )

      with subtest("Check last version of the extension after postgresql upgrade"):
        test.assert_version_matches(last_version)

      with subtest("Check upgrade path with postgresql 17"):
        test.check_upgrade_path("17")

      with subtest("Check pg_regress with postgresql 17 after extension upgrade"):
        test.check_pg_regress(Path("${psql_17}/lib/pgxs/src/test/regress/pg_regress"), "17", pg_regress_test_name)

      with subtest("Check the install of the last version of the extension"):
        test.check_install_last_version("17")

      with subtest("Check pg_regress with postgresql 17 after installing the last version"):
        test.check_pg_regress(Path("${psql_17}/lib/pgxs/src/test/regress/pg_regress"), "17", pg_regress_test_name)

      with subtest("switch to orioledb 17"):
        server.succeed(
          "${orioledb17-configuration}/bin/switch-to-configuration test >&2"
        )
        installed_extensions=test.run_sql("""SELECT extname FROM pg_extension WHERE extname = 'orioledb';""")
        assert "orioledb" in installed_extensions
        test.create_schema()

      with subtest("Check upgrade path with orioledb 17"):
        test.check_upgrade_path("orioledb-17")

      # NOTE: pg_regress tests are currently disabled for OrioleDB due to compatibility issues
      # The standard pg_regress test framework does not currently work with OrioleDB's
      # specialized storage engine, causing test failures that need investigation.
      #
      # TODO: Re-enable once OrioleDB pg_regress compatibility is resolved
      # with subtest("Check pg_regress with orioledb 17 after installing the last version"):
      #   test.check_pg_regress(Path("${orioledb_17}/lib/pgxs/src/test/regress/pg_regress"), "orioledb-17", pg_regress_test_name)
    '';
}
