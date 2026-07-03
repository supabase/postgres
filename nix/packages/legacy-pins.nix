{ ... }:
{
  perSystem =
    { self'
    , lib
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

      psql_17_6_1_025_with_latest_supautils =
        let
          oldPsql = postgres_17_6_1_025."psql_17/bin";
          supautils = self'.legacyPackages.psql_17.exts.supautils;
        in
        pkgs.runCommand "${oldPsql.name}-supautils-${supautils.version}"
          {
            inherit (oldPsql) version;
            nativeBuildInputs = [ pkgs.jq ];
          }
          ''
            cp -a ${oldPsql}/. $out/
            chmod -R u+w $out

            rm -f $out/lib/supautils${pkgs.stdenv.hostPlatform.extensions.sharedLibrary}
            ln -s ${supautils}/lib/* $out/lib/

            jq --arg version '${supautils.version}' \
              '(.extensions[] | select(.name == "supautils") | .version) = $version' \
              $out/receipt.json > $out/receipt.json.tmp
            mv $out/receipt.json.tmp $out/receipt.json
          '';
    in
    {
      packages = lib.optionalAttrs pkgs.stdenv.isLinux {
        "psql_17/bin" = lib.mkForce psql_17_6_1_025_with_latest_supautils;
        postgresql_17_debug = lib.mkForce postgres_17_6_1_025.postgresql_17_debug;
        postgresql_17_src = lib.mkForce postgres_17_6_1_025.postgresql_17_src;
        supabase-groonga = lib.mkForce postgres_17_6_1_025.supabase-groonga;
      };
    };
}
