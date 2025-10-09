{ self, pkgs }:
let
  pname = "timescaledb";
  inherit (pkgs) lib;
  installedExtension =
    postgresMajorVersion: self.packages.${pkgs.system}."psql_${postgresMajorVersion}/exts/${pname}-all";
  versions = (installedExtension "15").versions;
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
in
self.inputs.nixpkgs.lib.nixos.runTest {
  name = "timescaledb";
  hostPkgs = pkgs;
  nodes.server =
    { ... }:
    {
      services.postgresql = {
        enable = true;
        package = (postgresqlWithExtension psql_15);
        settings = {
          shared_preload_libraries = "timescaledb";
        };
      };
    };
  testScript =
    { ... }:
    ''
      ${builtins.readFile ./lib.py}

      start_all()

      server.wait_for_unit("multi-user.target")
      server.wait_for_unit("postgresql.service")

      versions = {
        "15": [${lib.concatStringsSep ", " (map (s: ''"${s}"'') versions)}],
      }
      extension_name = "${pname}"
      support_upgrade = True
      sql_test_directory = Path("${../../tests}")

      test = PostgresExtensionTest(server, extension_name, versions, sql_test_directory, support_upgrade)

      with subtest("Check upgrade path with postgresql 15"):
        test.check_upgrade_path("15")

      with subtest("Test switch_${pname}_version"):
        test.check_switch_extension_with_background_worker(Path("${psql_15}/lib/${pname}.so"), "15")
    '';
}
