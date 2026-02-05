{ self, pkgs }:
let
  pname = "orioledb";
  inherit (pkgs) lib;
  postgresqlWithExtension =
    postgresql:
    let
      majorVersion = lib.versions.major postgresql.version;
      pkg = pkgs.pkgsLinux.buildEnv {
        name = "postgresql-${majorVersion}-${pname}";
        paths = [
          postgresql
          postgresql.lib
          (self.legacyPackages.${pkgs.pkgsLinux.stdenv.hostPlatform.system}."psql_orioledb-17".exts.orioledb)
        ];
        passthru = {
          inherit (postgresql) version psqlSchema;
          installedExtensions = [
            (self.legacyPackages.${pkgs.pkgsLinux.stdenv.hostPlatform.system}."psql_orioledb-17".exts.orioledb)
          ];
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
  psql_orioledb =
    postgresqlWithExtension
      self.packages.${pkgs.pkgsLinux.stdenv.hostPlatform.system}.postgresql_orioledb-17;
in
pkgs.testers.runNixOSTest {
  name = pname;
  nodes.server =
    { ... }:
    {
      services.openssh = {
        enable = true;
      };

      services.postgresql = {
        enable = true;
        package = psql_orioledb;
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
    };
  testScript =
    { ... }:
    ''
      start_all()

      server.wait_for_unit("multi-user.target")
      server.wait_for_unit("postgresql.service")
    '';
}
