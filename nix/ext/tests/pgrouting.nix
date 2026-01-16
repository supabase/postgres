{ self, pkgs }:
let
  pname = "pgrouting";
  inherit (pkgs) lib;
  installedExtension =
    postgresMajorVersion:
    self.legacyPackages.${pkgs.stdenv.hostPlatform.system}."psql_${postgresMajorVersion}".exts."${
      pname
    }";
  versions = postgresqlMajorVersion: (installedExtension postgresqlMajorVersion).versions;
  postgresqlWithExtension =
    postgresql:
    let
      majorVersion = lib.versions.major postgresql.version;
      pkg = pkgs.buildEnv {
        name = "postgresql-${majorVersion}-${pname}";
        paths = [
          postgresql
          postgresql.lib
          (installedExtension majorVersion)
          (self.legacyPackages.${pkgs.stdenv.hostPlatform.system}."psql_${majorVersion}".exts.postgis)
        ]
        ++ lib.optional (postgresql.isOrioleDB) (
          self.legacyPackages.${pkgs.stdenv.hostPlatform.system}."psql_orioledb-17".exts.orioledb
        );
        passthru = {
          inherit (postgresql) version psqlSchema;
          installedExtensions = [ (installedExtension majorVersion) ];
          lib = pkg;
          withPackages = _: pkg;
          withJIT = pkg;
          withoutJIT = pkg;
        };
        nativeBuildInputs = [ pkgs.makeWrapper ];
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
  pg_regress = pkgs.callPackage ../pg_regress.nix {
    postgresql = self.packages.${pkgs.stdenv.hostPlatform.system}.postgresql_15;
  };
in
self.inputs.nixpkgs.lib.nixos.runTest {
  name = pname;
  hostPkgs = pkgs;
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
      users.users.root.openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIo+ulCUfJjnCVgfM4946Ih5Nm8DeZZiayYeABHGPEl7 jfroche"
      ];

      services.postgresql = {
        enable = true;
        package = postgresqlWithExtension self.packages.${pkgs.stdenv.hostPlatform.system}.postgresql_15;
      };

      specialisation.postgresql17.configuration = {
        services.postgresql = {
          package = lib.mkForce (
            postgresqlWithExtension self.packages.${pkgs.stdenv.hostPlatform.system}.postgresql_17
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
                  self.packages.${pkgs.stdenv.hostPlatform.system}.postgresql_15;
              newPostgresql =
                postgresqlWithExtension
                  self.packages.${pkgs.stdenv.hostPlatform.system}.postgresql_17;
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
            postgresqlWithExtension self.packages.${pkgs.stdenv.hostPlatform.system}.postgresql_orioledb-17
          );
          settings = {
            shared_preload_libraries = "orioledb";
            default_table_access_method = "orioledb";
          };
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
                  self.packages.${pkgs.stdenv.hostPlatform.system}.postgresql_orioledb-17;
            in
            ''
              set -x
              systemctl cat postgresql.service
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
      versions = {
        "15": [${lib.concatStringsSep ", " (map (s: ''"${s}"'') (versions "15"))}],
        "17": [${lib.concatStringsSep ", " (map (s: ''"${s}"'') (versions "17"))}],
        "orioledb-17": [${lib.concatStringsSep ", " (map (s: ''"${s}"'') (versions "orioledb-17"))}],
      }

      def run_sql(query):
        return server.succeed(f"""sudo -u postgres psql -t -A -F\",\" -c \"{query}\" """).strip()

      def run_pg_regress(sql_file, pg_version):
        try:
          server.succeed(f"""sudo -u postgres ${pg_regress}/bin/pg_regress --inputdir=${../../tests} --use-existing --dbname=postgres --outputdir=/tmp/regression_output_{pg_version} "{sql_file}" """)
        except:
          server.copy_from_vm(f"/tmp/regression_output_{pg_version}", "")
          raise

      def check_upgrade_path(pg_version):
        with subtest("Check ${pname} upgrade path"):
          firstVersion = versions[pg_version][0]
          server.succeed("sudo -u postgres psql -c 'DROP EXTENSION IF EXISTS ${pname};'")
          run_sql(f"""CREATE EXTENSION ${pname} WITH VERSION '{firstVersion}' CASCADE;""")
          installed_version = run_sql(r"""SELECT extversion FROM pg_extension WHERE extname = '${pname}';""")
          assert installed_version == firstVersion, f"Expected ${pname} version {firstVersion}, but found {installed_version}"
          for version in versions[pg_version][1:]:
            run_sql(f"""ALTER EXTENSION ${pname} UPDATE TO '{version}';""")
            installed_version = run_sql(r"""SELECT extversion FROM pg_extension WHERE extname = '${pname}';""")
            assert installed_version == version, f"Expected ${pname} version {version}, but found {installed_version}"
          run_pg_regress("${pname}", pg_version)

      start_all()

      server.wait_for_unit("multi-user.target")
      server.wait_for_unit("postgresql.service")

      check_upgrade_path("15")

      with subtest("Check ${pname} latest extension version"):
        server.succeed("sudo -u postgres psql -c 'DROP EXTENSION ${pname};'")
        server.succeed("sudo -u postgres psql -c 'CREATE EXTENSION ${pname} CASCADE;'")
        installed_extensions=run_sql(r"""SELECT extname, extversion FROM pg_extension;""")
        latestVersion = versions["15"][-1]
        assert f"${pname},{latestVersion}" in installed_extensions

      with subtest("switch to postgresql 17"):
        server.succeed(
          "${pg17-configuration}/bin/switch-to-configuration test >&2"
        )

      with subtest("Check ${pname} latest extension version after upgrade"):
        installed_extensions=run_sql(r"""SELECT extname, extversion FROM pg_extension;""")
        latestVersion = versions["17"][-1]
        assert f"${pname},{latestVersion}" in installed_extensions

      check_upgrade_path("17")

      with subtest("switch to orioledb 17"):
        server.succeed(
          "${orioledb17-configuration}/bin/switch-to-configuration test >&2"
        )
        installed_extensions=run_sql(r"""SELECT extname FROM pg_extension WHERE extname = 'orioledb';""")
        assert "orioledb" in installed_extensions

      check_upgrade_path("orioledb-17")
    '';
}
