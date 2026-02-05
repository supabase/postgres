{ self, pkgs }:
let
  pname = "http";
  inherit (pkgs) lib;
  mockServer = ../../tests/http-mock-server.py;
  installedExtension =
    postgresMajorVersion:
    self.legacyPackages.${pkgs.pkgsLinux.stdenv.hostPlatform.system}."psql_${postgresMajorVersion}".exts."${
      pname
    }";
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
        package =
          postgresqlWithExtension
            self.packages.${pkgs.pkgsLinux.stdenv.hostPlatform.system}.postgresql_15;
        settings = (installedExtension "15").defaultSettings or { };
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
        initialScript = pkgs.writeText "init-postgres" ''
          CREATE TABLE IF NOT EXISTS test_config (key TEXT PRIMARY KEY, value TEXT);
        '';
      };

      systemd.services.http-mock-server = {
        wantedBy = [ "multi-user.target" ];
        before = [ "postgresql.service" ];
        serviceConfig = {
          Type = "simple";
          Restart = "on-failure";
          RestartSec = "2";
          TimeoutStartSec = "30";
          User = "root";
        };
        environment = {
          HTTP_MOCK_PORT_FILE = "/tmp/http-mock-port";
          PYTHONUNBUFFERED = "1";
        };
        script = ''
          # Ensure temp directory exists
          mkdir -p /tmp

          # Start the mock server
          exec ${pkgs.pkgsLinux.python3}/bin/python3 ${mockServer}
        '';
      };

      systemd.services.postgresql = {
        after = [ "http-mock-server.service" ];
      };

      specialisation.postgresql17.configuration = {
        services.postgresql = {
          package = lib.mkForce (
            postgresqlWithExtension self.packages.${pkgs.pkgsLinux.stdenv.hostPlatform.system}.postgresql_17
          );
          settings = ((installedExtension "17").defaultSettings or { });
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
              oldPostgresql =
                postgresqlWithExtension
                  self.packages.${pkgs.pkgsLinux.stdenv.hostPlatform.system}.postgresql_15;
              newPostgresql =
                postgresqlWithExtension
                  self.packages.${pkgs.pkgsLinux.stdenv.hostPlatform.system}.postgresql_17;
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
          initialScript = lib.mkForce (
            pkgs.writeText "init-postgres-with-orioledb" ''
              CREATE EXTENSION orioledb CASCADE;
              CREATE TABLE IF NOT EXISTS test_config (key TEXT PRIMARY KEY, value TEXT);
            ''
          );
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
      # Convert versions to major.minor format (e.g., "1.5.0" -> "1.5")
      toMajorMinor = map (v: lib.versions.majorMinor v);
    in
    ''
      from pathlib import Path
      versions = {
         "15": [${lib.concatStringsSep ", " (map (s: ''"${s}"'') (toMajorMinor (versions "15")))}],
         "17": [${lib.concatStringsSep ", " (map (s: ''"${s}"'') (toMajorMinor (versions "17")))}],
        "orioledb-17": [${
          lib.concatStringsSep ", " (map (s: ''"${s}"'') (toMajorMinor (versions "orioledb-17")))
        }],
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
      server.wait_for_unit("http-mock-server.service")
      server.wait_for_unit("postgresql.service")

      # Read the HTTP mock port and configure it in PostgreSQL
      # Wait for the port file to be created with retry logic
      server.succeed("""
        for i in {1..30}; do
          if [ -f /tmp/http-mock-port ]; then
            break
          fi
          echo "Waiting for HTTP mock server port file... ($i/30)"
          sleep 1
        done
        
        if [ ! -f /tmp/http-mock-port ]; then
          echo "ERROR: HTTP mock server port file not found after 30 seconds"
          systemctl status http-mock-server.service || true
          journalctl -u http-mock-server.service --no-pager || true
          exit 1
        fi
      """)

      http_port = server.succeed("cat /tmp/http-mock-port").strip()
      server.succeed(f"""
        sudo -u postgres psql -d postgres -c '
          CREATE TABLE IF NOT EXISTS test_config (key TEXT PRIMARY KEY, value TEXT);
          INSERT INTO test_config (key, value) VALUES ('"'"'http_mock_port'"'"', '"'"'{http_port}'"'"')
          ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
        '
      """)

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
        server.wait_for_unit("postgresql.service")
        # Reconfigure the HTTP mock port after switching PostgreSQL version
        server.succeed(f"""
          sudo -u postgres psql -d postgres -c '
            INSERT INTO test_config (key, value) VALUES ('"'"'http_mock_port'"'"', '"'"'{http_port}'"'"')
            ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
          '
        """)

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
        server.wait_for_unit("postgresql.service")
        # Reconfigure the HTTP mock port after switching to orioledb
        server.succeed(f"""
          sudo -u postgres psql -d postgres -c '
            INSERT INTO test_config (key, value) VALUES ('"'"'http_mock_port'"'"', '"'"'{http_port}'"'"')
            ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
          '
        """)
        installed_extensions=test.run_sql("""SELECT extname FROM pg_extension WHERE extname = 'orioledb';""")
        assert "orioledb" in installed_extensions
        test.create_schema()

      with subtest("Check upgrade path with orioledb 17"):
        test.check_upgrade_path("orioledb-17")

      with subtest("Check pg_regress with orioledb 17 after installing the last version"):
        test.check_pg_regress(Path("${orioledb_17}/lib/pgxs/src/test/regress/pg_regress"), "orioledb-17", pg_regress_test_name)
    '';
}
# We don't use the generic test for this extension because:
# http is not using semver versioning scheme, so we need to adapt the version checks
# otherwise the test fails with ERROR:  extension "http" has no installation script nor update path for version "1.5.0"
