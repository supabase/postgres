{ self, pkgs }:
let
  inherit (pkgs) lib;
  installedExtension =
    postgresMajorVersion:
    self.packages.${pkgs.system}."psql_${postgresMajorVersion}/exts/timescaledb-all";
  versions = (installedExtension "15").versions;
  firstVersion = lib.head versions;
  postgresqlWithExtension =
    postgresql:
    let
      majorVersion = lib.versions.major postgresql.version;
      pkg = pkgs.buildEnv {
        name = "postgresql-${majorVersion}-timescaledb";
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
in
self.inputs.nixpkgs.lib.nixos.runTest {
  name = "timescaledb";
  hostPkgs = pkgs;
  nodes.server =
    { ... }:
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
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIArkmq6Th79Z4klW6Urgi4phN8yq769/l/10jlE00tU9"
      ];

      services.postgresql = {
        enable = true;
        package = postgresqlWithExtension self.packages.${pkgs.system}.postgresql_15;
        settings = {
          shared_preload_libraries = "timescaledb";
        };
      };

      specialisation.postgresql15.configuration = {
        services.postgresql = {
          package = lib.mkForce (postgresqlWithExtension self.packages.${pkgs.system}.postgresql_15);
        };
      };
    };
  testScript =
    { ... }:
    ''
      def run_sql(query):
          return server.succeed(f"""sudo -u postgres psql -t -A -F\",\" -c \"{query}\" """).strip()

      def check_upgrade_path():
          with subtest("Check timescaledb upgrade path"):
              server.succeed("sudo -u postgres psql -c 'DROP EXTENSION IF EXISTS timescaledb;'")
              run_sql(r"""CREATE EXTENSION timescaledb WITH VERSION \"${firstVersion}\";""")
              installed_version = run_sql(r"""SELECT extversion FROM pg_extension WHERE extname = 'timescaledb';""")
              assert installed_version == "${firstVersion}", f"Expected timescaledb version ${firstVersion}, but found {installed_version}"
              for version in [${lib.concatStringsSep ", " (map (s: ''"${s}"'') versions)}][1:]:
                  run_sql(f"""ALTER EXTENSION timescaledb UPDATE TO '{version}';""")
                  installed_version = run_sql(r"""SELECT extversion FROM pg_extension WHERE extname = 'timescaledb';""")
                  assert installed_version == version, f"Expected timescaledb version {version}, but found {installed_version}"

      start_all()

      server.wait_for_unit("multi-user.target")
      server.wait_for_unit("postgresql.service")

      check_upgrade_path()
    '';
}
