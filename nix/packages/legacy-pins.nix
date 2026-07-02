{ ... }:
{
  perSystem =
    { lib
    , pkgs
    , system
    , ...
    }:
    let
      # Rebuild old 17.6.1.025 release as an x86_64 linux AMI.
      # Reuse old packages from the legacy flake to avoid version differences in postgresql and extensions.
      postgres_17_6_1_025 =
        # tag 17.6.1.025
        (builtins.getFlake "github:supabase/postgres/d99dc84674bae03e0bf1feebc68dcfbc0cb989a3").packages.${system};
    in
    {
      packages = lib.optionalAttrs pkgs.stdenv.isLinux {
        "psql_17/bin" = lib.mkForce postgres_17_6_1_025."psql_17/bin";
        postgresql_17_debug = lib.mkForce postgres_17_6_1_025.postgresql_17_debug;
        postgresql_17_src = lib.mkForce postgres_17_6_1_025.postgresql_17_src;
        supabase-groonga = lib.mkForce postgres_17_6_1_025.supabase-groonga;
      };
    };
}
