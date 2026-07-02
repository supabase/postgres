{ ... }:
{
  perSystem =
    {
      lib,
      pkgs,
      system,
      ...
    }:
    let
      # Rebuild old 17.6.1.013 release as an x86_64 linux AMI.
      # Reuse old packages from the legacy flake to avoid version differences in postgresql and extensions.
      postgres_17_6_1_013 =
        # tag 17.6.1.013
        (builtins.getFlake "github:supabase/postgres/e4308280107035cf7a2590d696aed0e9713bed3a")
        .packages.${system};
    in
    {
      packages = lib.optionalAttrs pkgs.stdenv.isLinux {
        "psql_17/bin" = lib.mkForce postgres_17_6_1_013."psql_17/bin";
        postgresql_17_debug = lib.mkForce postgres_17_6_1_013.postgresql_17_debug;
        postgresql_17_src = lib.mkForce postgres_17_6_1_013.postgresql_17_src;
        supabase-groonga = lib.mkForce postgres_17_6_1_013.supabase-groonga;
      };
    };
}
