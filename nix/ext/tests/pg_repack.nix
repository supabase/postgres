{ self, pkgs }:
let
  pname = "pg_repack";
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

      networking.firewall.allowedTCPPorts = [ config.services.postgresql.settings.port ];

      specialisation.postgresql17.configuration = {
        services.postgresql = {
          package = lib.mkForce (
            postgresqlWithExtension self.packages.${pkgs.pkgsLinux.stdenv.hostPlatform.system}.postgresql_17
          );
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
      support_upgrade = False
      pg17_configuration = "${pg17-configuration}"
      sql_test_directory = Path("${../../tests}")

      ${builtins.readFile ./lib.py}

      start_all()

      server.wait_for_unit("multi-user.target")
      server.wait_for_unit("postgresql.service")

      test = PostgresExtensionTest(server, extension_name, versions, sql_test_directory, support_upgrade)

      with subtest("Check upgrade path with postgresql 15"):
        test.check_upgrade_path("15")

      last_version = None
      with subtest("Check the install of the last version of the extension"):
        last_version = test.check_install_last_version("15")

      with subtest("switch to postgresql 17"):
        server.succeed(
          f"{pg17_configuration}/bin/switch-to-configuration test >&2"
        )

      with subtest("Check last version of the extension after upgrade"):
        test.assert_version_matches(last_version)

      with subtest("Check upgrade path with postgresql 17"):
        test.check_upgrade_path("17")
    '';
}
# We don't use the generic test for this extension because:
# pg_repack does not support upgrade as the extension doesn't provide the upgrade SQL scripts
# and fails with ERROR:  extension "pg_repack" has no update path from version "1.4.8" to version "1.5.0"
