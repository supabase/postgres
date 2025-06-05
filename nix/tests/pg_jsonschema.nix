{ self, pkgs }:
let
  inherit (pkgs) lib;
  installedExtension = postgresMajorVersion:
    self.packages.${pkgs.system}."psql_${postgresMajorVersion}/exts/pg_jsonschema-all";
  versions = postgresqlMajorVersion: (installedExtension postgresqlMajorVersion).versions;
  postgresqlWithExtension = postgresql:
    let
      majorVersion = lib.versions.major postgresql.version;
      pkg = pkgs.buildEnv {
        name = "postgresql-${majorVersion}-pg_jsonschema";
        paths = [ postgresql postgresql.lib (installedExtension majorVersion) ];
        passthru = {
          inherit (postgresql) version psqlSchema;
          lib = pkg;
          withPackages = _: pkg;
        };
        nativeBuildInputs = [ pkgs.makeWrapper ];
        pathsToLink = [ "/" "/bin" "/lib" ];
        postBuild = ''
          wrapProgram $out/bin/postgres --set NIX_PGLIBDIR $out/lib
          wrapProgram $out/bin/pg_ctl --set NIX_PGLIBDIR $out/lib
          wrapProgram $out/bin/pg_upgrade --set NIX_PGLIBDIR $out/lib
        '';
      };
    in pkg;
in self.inputs.nixpkgs.lib.nixos.runTest {
  name = "pg_jsonschema";
  hostPkgs = pkgs;
  nodes.server = { config, ... }: {
    virtualisation = {
      forwardPorts = [{
        from = "host";
        host.port = 13022;
        guest.port = 22;
      }];
    };
    services.openssh = { enable = true; };
    users.users.root.openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIo+ulCUfJjnCVgfM4946Ih5Nm8DeZZiayYeABHGPEl7 jfroche"
    ];

    services.postgresql = {
      enable = true;
      package =
        postgresqlWithExtension self.packages.${pkgs.system}.postgresql_15;
    };

    specialisation.postgresql17.configuration = {
      services.postgresql = {
        package = lib.mkForce
          (postgresqlWithExtension self.packages.${pkgs.system}.postgresql_17);
      };

      systemd.services.postgresql-migrate = {
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = "postgres";
          Group = "postgres";
          StateDirectory = "postgresql";
          WorkingDirectory =
            "${builtins.dirOf config.services.postgresql.dataDir}";
        };
        script = let
          oldPostgresql =
            postgresqlWithExtension self.packages.${pkgs.system}.postgresql_15;
          newPostgresql =
            postgresqlWithExtension self.packages.${pkgs.system}.postgresql_17;
          oldDataDir = "${
              builtins.dirOf config.services.postgresql.dataDir
            }/${oldPostgresql.psqlSchema}";
          newDataDir = "${
              builtins.dirOf config.services.postgresql.dataDir
            }/${newPostgresql.psqlSchema}";
        in ''
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
  testScript = { nodes, ... }:
    let
      pg17-configuration =
        "${nodes.server.system.build.toplevel}/specialisation/postgresql17";
    in ''
      versions = {
        "15": [${lib.concatStringsSep ", " (map (s: ''"${s}"'') (versions "15"))}],
        "17": [${lib.concatStringsSep ", " (map (s: ''"${s}"'') (versions "17"))}],
      }

      def run_sql(query):
        return server.succeed(f"""sudo -u postgres psql -t -A -F\",\" -c \"{query}\" """).strip()

      def check_upgrade_path(pg_version):
        with subtest("Check pg_jsonschema upgrade path"):
          firstVersion = versions[pg_version][0]
          server.succeed("sudo -u postgres psql -c 'DROP EXTENSION IF EXISTS pg_jsonschema;'")
          run_sql(f"""CREATE EXTENSION pg_jsonschema WITH VERSION '{firstVersion}';""")
          installed_version = run_sql(r"""SELECT extversion FROM pg_extension WHERE extname = 'pg_jsonschema';""")
          assert installed_version == firstVersion, f"Expected pg_jsonschema version {firstVersion}, but found {installed_version}"
          for version in versions[pg_version][1:]:
            run_sql(f"""ALTER EXTENSION pg_jsonschema UPDATE TO '{version}';""")
            installed_version = run_sql(r"""SELECT extversion FROM pg_extension WHERE extname = 'pg_jsonschema';""")
            assert installed_version == version, f"Expected pg_jsonschema version {version}, but found {installed_version}"

      start_all()

      server.wait_for_unit("multi-user.target")
      server.wait_for_unit("postgresql.service")

      check_upgrade_path("15")

      with subtest("Check pg_jsonschema latest extension version"):
        server.succeed("sudo -u postgres psql -c 'DROP EXTENSION pg_jsonschema;'")
        server.succeed("sudo -u postgres psql -c 'CREATE EXTENSION pg_jsonschema;'")
        installed_extensions=run_sql(r"""SELECT extname, extversion FROM pg_extension;""")
        latestVersion = versions["15"][-1]
        assert f"pg_jsonschema,{latestVersion}" in installed_extensions

      with subtest("switch to postgresql 17"):
        server.succeed(
          "${pg17-configuration}/bin/switch-to-configuration test >&2"
        )

      with subtest("Check pg_jsonschema latest extension version"):
        installed_extensions=run_sql(r"""SELECT extname, extversion FROM pg_extension;""")
        latestVersion = versions["17"][-1]
        assert f"pg_jsonschema,{latestVersion}" in installed_extensions

      check_upgrade_path("17")
    '';
}
