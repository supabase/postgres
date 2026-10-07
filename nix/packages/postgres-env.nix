{
  perSystem =
    {
      lib,
      pkgs,
      self',
      ...
    }:
    let
      # Make a bundle of packages, as a single derivation, to be installed into the
      # postgres user's nix profile, during image provisioning or instance update.
      makePostgresEnv =
        version:
        pkgs.symlinkJoin {
          name = "postgres-env-${version}";
          paths = [
            self'.packages."psql_${version}/bin"
            self'.packages.pg_prove
            self'.packages.supabase-groonga
          ]
          ++ lib.optionals (pkgs.stdenv.isLinux && version != "15") [ self'.packages.gatekeeper ];
        };

      makePostgresEnvDebug =
        version:
        pkgs.symlinkJoin {
          name = "postgres-env-${version}-debug";
          paths = [
            self'.packages."postgresql_${version}_src"
          ]
          ++ lib.optionals pkgs.stdenv.isLinux [ self'.packages."postgresql_${version}_debug" ]
          # orioledb.so ships as a separate extension package (nix/ext/orioledb.nix), not
          # part of the postgresql derivation itself, so its debug output isn't covered by
          # postgresql_${version}_debug above and has to be pulled in explicitly.
          ++ lib.optionals (pkgs.stdenv.isLinux && version == "orioledb-17") [
            self'.legacyPackages."psql_${version}".exts.orioledb.debug
          ];
        };
    in
    {
      packages = {
        postgres-env-15 = makePostgresEnv "15";
        postgres-env-17 = makePostgresEnv "17";
        postgres-env-orioledb-17 = makePostgresEnv "orioledb-17";
        postgres-env-15-debug = makePostgresEnvDebug "15";
        postgres-env-17-debug = makePostgresEnvDebug "17";
        postgres-env-orioledb-17-debug = makePostgresEnvDebug "orioledb-17";
      };
    };
}
