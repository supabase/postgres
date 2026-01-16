{ self, pkgs }:
let
  pname = "timescaledb";
  inherit (pkgs) lib;
  installedExtension =
    postgresMajorVersion:
    self.legacyPackages.${pkgs.stdenv.hostPlatform.system}."psql_${postgresMajorVersion}".exts."${
      pname
    }";
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
  psql_15 = postgresqlWithExtension self.packages.${pkgs.stdenv.hostPlatform.system}.postgresql_15;
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
          { name = "service_role"; }
        ];

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

      test = PostgresExtensionTest(server, extension_name, versions, sql_test_directory, support_upgrade, "public", "timescaledb-loader")

      with subtest("Check upgrade path with postgresql 15"):
        test.check_upgrade_path("15")

      with subtest("Test switch_${pname}_version"):
        test.check_switch_extension_with_background_worker(Path("${psql_15}/lib/timescaledb-loader.so"), "15")
    '';
}
