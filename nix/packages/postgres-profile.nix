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
      makePostgresProfile =
        version:
        pkgs.symlinkJoin {
          name = "postgres-profile-${version}";
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
        postgres-profile-15 = makePostgresProfile "15";
        postgres-profile-17 = makePostgresProfile "17";
        postgres-profile-orioledb-17 = makePostgresProfile "orioledb-17";
      };
    };
}
