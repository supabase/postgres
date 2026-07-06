{ ... }:
{
  perSystem =
    {
      self',
      lib,
      pkgs,
      system,
      ...
    }:
    let
      # Rebuild old release as an x86_64 linux AMI.
      # Reuse old packages from the legacy flake to avoid version differences in postgresql and extensions.
      postgres_old =
        # tag 17.6.1.104
        (builtins.getFlake "github:supabase/postgres/2997c92770dd85e6450e3e2c7d2c843f4717f492")
        .packages.${system};

      psql_old_with_latest_supautils =
        let
          oldPsql = postgres_old."psql_17/bin";
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

            # update receipt
            jq --arg version '${supautils.version}' \
              '(.extensions[] | select(.name == "supautils") | .version) = $version' \
              $out/receipt.json > $out/receipt.json.tmp
            mv $out/receipt.json.tmp $out/receipt.json
          '';
    in
    {
      packages = lib.optionalAttrs pkgs.stdenv.isLinux {
        "psql_17/bin" = lib.mkForce psql_old_with_latest_supautils;
        postgresql_17_debug = lib.mkForce postgres_old.postgresql_17_debug;
        postgresql_17_src = lib.mkForce postgres_old.postgresql_17_src;
        supabase-groonga = lib.mkForce postgres_old.supabase-groonga;
      };
    };
}
