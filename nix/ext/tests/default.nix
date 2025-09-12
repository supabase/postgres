{ self, pkgs }:
let
  testsDir = ./.;
  testFiles = builtins.attrNames (builtins.readDir testsDir);
  nixFiles = builtins.filter (
    name: builtins.match ".*\\.nix$" name != null && name != "default.nix"
  ) testFiles;
  extTest =
    extension_name:
    let
      pname = extension_name;
      inherit (pkgs) lib;
      installedExtension =
        postgresMajorVersion: self.packages.${pkgs.system}."psql_${postgresMajorVersion}/exts/${pname}-all";
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

          services.postgresql = {
            enable = true;
            package = psql_15;
            enableTCPIP = true;
            initialScript = pkgs.writeText "init-postgres-with-password" ''
              CREATE USER test WITH PASSWORD 'secret';
            '';
            authentication = ''
              host test postgres samenet scram-sha-256
            '';
            settings = (installedExtension "15").defaultSettings or { };
          };

          networking.firewall.allowedTCPPorts = [ config.services.postgresql.settings.port ];

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
          versions = {
            "15": [${lib.concatStringsSep ", " (map (s: ''"${s}"'') (versions "15"))}],
            "17": [${lib.concatStringsSep ", " (map (s: ''"${s}"'') (versions "17"))}],
          }
          extension_name = "${pname}"
          support_upgrade = True
          pg17_configuration = "${pg17-configuration}"
          ext_has_background_worker = ${
            if (installedExtension "15") ? hasBackgroundWorker then "True" else "False"
          }

          ${builtins.readFile ./lib.py}

          start_all()

          server.wait_for_unit("multi-user.target")
          server.wait_for_unit("postgresql.service")

          test = PostgresExtensionTest(server, extension_name, versions, support_upgrade)

          with subtest("Check upgrade path with postgresql 15"):
            test.check_upgrade_path("15")

          last_version = None
          with subtest("Check the install of the last version of the extension"):
            last_version = test.check_install_last_version("15")

          if ext_has_background_worker:
            with subtest("Test switch_${pname}_version"):
              test.check_switch_extension_with_background_worker(Path("${psql_15}/lib/${pname}.so"), "15")

          with subtest("switch to postgresql 17"):
            server.succeed(
              f"{pg17_configuration}/bin/switch-to-configuration test >&2"
            )

          with subtest("Check last version of the extension after upgrade"):
            test.assert_version_matches(last_version)

          with subtest("Check upgrade path with postgresql 17"):
            test.check_upgrade_path("17")
        '';
    };
in
builtins.listToAttrs (
  map (file: {
    name = "ext-" + builtins.replaceStrings [ ".nix" ] [ "" ] file;
    value = import (testsDir + "/${file}") { inherit self pkgs; };
  }) nixFiles
)
// builtins.listToAttrs (
  map
    (extName: {
      name = "ext-${extName}";
      value = extTest extName;
    })
    [
      "index_advisor"
      "pg_cron"
      "pg_net"
      "vector"
      "wrappers"
    ]
)
