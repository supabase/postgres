{ self, pkgs }:
let
  inherit (pkgs) lib;
  installedExtension =
    postgresMajorVersion: self.packages.${pkgs.system}."psql_${postgresMajorVersion}/exts/pg_net-all";
  versions = (installedExtension "17").versions;
  firstVersion = lib.head versions;
  latestVersion = lib.last versions;
  postgresqlWithExtension =
    postgresql:
    let
      majorVersion = lib.versions.major postgresql.version;
      pkg = pkgs.buildEnv {
        name = "postgresql-${majorVersion}-pg_net";
        paths = [
          postgresql
          postgresql.lib
          (installedExtension majorVersion)
        ];
        passthru = {
          inherit (postgresql) version psqlSchema;
          lib = pkg;
          withPackages = _: pkg;
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
  psql_15 = postgresqlWithExtension self.packages.${pkgs.system}.postgresql_15;
  psql_17 = postgresqlWithExtension self.packages.${pkgs.system}.postgresql_17;
in
self.inputs.nixpkgs.lib.nixos.runTest {
  name = "pg_net";
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
        package = psql_15;
        settings = {
          shared_preload_libraries = "pg_net";
        };
      };

      specialisation.postgresql17.configuration = {
        services.postgresql = {
          package = lib.mkForce psql_17;
        };

        environment.systemPackages = [ psql_17 ];

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
              oldPostgresql = postgresqlWithExtension self.packages.${pkgs.system}.postgresql_15;
              newPostgresql = postgresqlWithExtension self.packages.${pkgs.system}.postgresql_17;
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
      def run_sql(query):
        return server.succeed(f"""sudo -u postgres psql -t -A -F\",\" -c \"{query}\" """).strip()

      def check_upgrade_path():
        with subtest("Check pg_net upgrade path"):
          server.succeed("sudo -u postgres psql -c 'DROP EXTENSION IF EXISTS pg_net;'")
          run_sql(r"""CREATE EXTENSION pg_net WITH VERSION \"${firstVersion}\";""")
          installed_version = run_sql(r"""SELECT extversion FROM pg_extension WHERE extname = 'pg_net';""")
          assert installed_version == "${firstVersion}", f"Expected pg_net version ${firstVersion}, but found {installed_version}"
          for version in [${lib.concatStringsSep ", " (map (s: ''"${s}"'') versions)}][1:]:
            run_sql(f"""ALTER EXTENSION pg_net UPDATE TO '{version}';""")
            installed_version = run_sql(r"""SELECT extversion FROM pg_extension WHERE extname = 'pg_net';""")
            assert installed_version == version, f"Expected pg_net version {version}, but found {installed_version}"

      start_all()

      server.wait_for_unit("multi-user.target")
      server.wait_for_unit("postgresql.service")

      check_upgrade_path()

      with subtest("Test switch_pg_net_version"):
        # Check that we are using the last version first
        pg_net_version = server.succeed("readlink -f ${psql_15}/lib/pg_net.so").strip()
        print(f"Current pg_net version: {pg_net_version}")
        assert pg_net_version.endswith("pg_net-${latestVersion}.so"), f"Expected pg_net version ${latestVersion}, but found {pg_net_version}"

        server.succeed(
          "switch_pg_net_version ${firstVersion}"
        )

        pg_net_version = server.succeed("readlink -f ${psql_15}/lib/pg_net.so").strip()
        assert pg_net_version.endswith("pg_net-${firstVersion}.so"), f"Expected pg_net version ${firstVersion}, but found {pg_net_version}"

        server.succeed(
          "switch_pg_net_version ${latestVersion}"
        )

      with subtest("Check pg_net latest extension version"):
        server.succeed("sudo -u postgres psql -c 'DROP EXTENSION pg_net;'")
        server.succeed("sudo -u postgres psql -c 'CREATE EXTENSION pg_net;'")
        installed_extensions=run_sql(r"""SELECT extname, extversion FROM pg_extension;""")
        assert "pg_net,${latestVersion}" in installed_extensions

      with subtest("switch to multiple node configuration"):
        server.succeed(
          "${pg17-configuration}/bin/switch-to-configuration test >&2"
        )

      with subtest("Check pg_net latest extension version"):
        installed_extensions=run_sql(r"""SELECT extname, extversion FROM pg_extension;""")
        assert "pg_net,${latestVersion}" in installed_extensions

      check_upgrade_path()

    '';
}
