{
  perSystem =
    {
      lib,
      pkgs,
      self',
      ...
    }:
    let
      # Bundles everything the AMI build installs into the postgres user's nix
      # profile (via `nix-env --set`) into a single derivation.
      makePostgresEnv =
        version:
        pkgs.symlinkJoin {
          name = "postgres-env-${version}";
          paths = [
            self'.packages."psql_${version}/bin"
            self'.packages.pg_prove
            self'.packages.supabase-groonga
            self'.packages."postgresql_${version}_src"
          ]
          ++ lib.optionals pkgs.stdenv.isLinux [ self'.packages."postgresql_${version}_debug" ]
          ++ lib.optionals (pkgs.stdenv.isLinux && version != "15") [ self'.packages.gatekeeper ];
        };
    in
    {
      packages = {
        postgres-env-15 = makePostgresEnv "15";
        postgres-env-17 = makePostgresEnv "17";
        postgres-env-orioledb-17 = makePostgresEnv "orioledb-17";
      };
    };
}
