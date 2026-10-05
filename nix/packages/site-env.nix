# These are envs (package sets per pg major version) deployed to instances
# at /nix/var/nix/profiles/site and updated regularly.
{
  perSystem =
    {
      self',
      pkgs,
      lib,
      ...
    }:
    let
      activate = pkgs.writeShellApplication {
        name = "activate";
        text = ''
          echo "Activating site profile."
        '';
      };

      # supautils is no longer part of psql_${version}'s own extension set (it's
      # deployed exclusively through the site profile, not the base postgres
      # closure), so it's built directly here instead of via psql_${version}.exts.
      makeSiteEnv =
        version: extraPaths:
        pkgs.buildEnv {
          name = "site-env-${version}";
          paths = [
            (pkgs.callPackage ../ext/supautils.nix { postgresql = pkgs."postgresql_${version}"; })
            activate
          ]
          ++ extraPaths;
          postBuild = ''
            mkdir -p $out/pg-extensions
            ln -s ../lib/supautils.so $out/pg-extensions/supautils.so
          '';
        };

      siteEnvs = {

        "site-env-15" = makeSiteEnv "15" [ ];

        # gatekeeper is only available for pg 17+ on linux

        "site-env-17" = makeSiteEnv "17" (lib.optionals pkgs.stdenv.isLinux [ self'.packages.gatekeeper ]);

        "site-env-orioledb-17" = makeSiteEnv "orioledb-17" (
          lib.optionals pkgs.stdenv.isLinux [ self'.packages.gatekeeper ]
        );
      };
    in
    {
      packages = siteEnvs;
      legacyPackages = siteEnvs;
    };
}
