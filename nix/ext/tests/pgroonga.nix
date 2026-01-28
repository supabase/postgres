{ self, pkgs }:
let
  pname = "pgroonga";
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
      };
      systemd.services.postgresql.environment.MECAB_DICDIR = "${
        self.packages.${pkgs.pkgsLinux.stdenv.hostPlatform.system}.mecab-naist-jdic
      }/lib/mecab/dic/naist-jdic";
      systemd.services.postgresql.environment.MECAB_CONFIG = "${pkgs.pkgsLinux.mecab}/bin/mecab-config";
      systemd.services.postgresql.environment.GRN_PLUGINS_DIR = "${
        self.packages.${pkgs.pkgsLinux.stdenv.hostPlatform.system}.supabase-groonga
      }/lib/groonga/plugins";

      specialisation.postgresql17.configuration = {
        services.postgresql = {
          package = lib.mkForce psql_17;
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
    };
  testScript =
    { nodes, ... }:
    let
      pg17-configuration = "${nodes.server.system.build.toplevel}/specialisation/postgresql17";
    in
    ''
      from pathlib import Path
      versions = {
        "15": [${lib.concatStringsSep ", " (map (s: ''"${s}"'') (versions "15"))}],
        "17": [${lib.concatStringsSep ", " (map (s: ''"${s}"'') (versions "17"))}],
      }
      extension_name = "${pname}"
      pg17_configuration = "${pg17-configuration}"
      ext_has_background_worker = ${
        if (installedExtension "15") ? hasBackgroundWorker then "True" else "False"
      }
      sql_test_directory = Path("${../../tests}")
      pg_regress_test_name = "${(installedExtension "15").pgRegressTestName or pname}"

      ${builtins.readFile ./lib.py}

      start_all()

      server.wait_for_unit("multi-user.target")
      server.wait_for_unit("postgresql.service")

      test = PostgresExtensionTest(server, extension_name, versions, sql_test_directory)

      with subtest("Check upgrade path with postgresql 15"):
        test.check_upgrade_path("15")

      with subtest("Check pg_regress with postgresql 15 after extension upgrade"):
        test.check_pg_regress(Path("${psql_15}/lib/pgxs/src/test/regress/pg_regress"), "15", pg_regress_test_name)

      last_version = None
      with subtest("Check the install of the last version of the extension"):
        last_version = test.check_install_last_version("15")

      if ext_has_background_worker:
        with subtest("Test switch_${pname}_version"):
          test.check_switch_extension_with_background_worker(Path("${psql_15}/lib/${pname}.so"), "15")

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

      with subtest("Check pg_regress with postgresql 17 after extension upgrade"):
        test.check_pg_regress(Path("${psql_17}/lib/pgxs/src/test/regress/pg_regress"), "17", pg_regress_test_name)

      with subtest("Check the install of the last version of the extension"):
        test.check_install_last_version("17")

      with subtest("Check pg_regress with postgresql 17 after installing the last version"):
        test.check_pg_regress(Path("${psql_17}/lib/pgxs/src/test/regress/pg_regress"), "17", pg_regress_test_name)
    '';
}
