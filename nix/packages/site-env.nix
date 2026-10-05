# These are envs (package sets per pg major version) deployed to instances
# at /nix/var/nix/profiles/site and updated regularly.
{ inputs, ... }:
{
  perSystem =
    {
      self',
      pkgs,
      lib,
      ...
    }:
    let
      # Built from the main nixpkgs. Both are dlopen'd into postgres without an
      # RPATH, so they run against the postgres process's glibc.
      supautils =
        version:
        pkgs.callPackage ../ext/supautils.nix { postgresql = self'.packages."postgresql_${version}"; };
      gatekeeper = pkgs.callPackage ./gatekeeper.nix { inherit inputs pkgs; };

      makeSiteEnv =
        version: extraPaths:
        pkgs.buildEnv {
          name = "site-env-${version}";
          paths = [ (supautils version) ] ++ extraPaths;
        };

      siteEnvs = {

        "site-env-15" = makeSiteEnv "15" [ ];

        # gatekeeper is only available for pg 17+ on linux

        "site-env-17" = makeSiteEnv "17" (lib.optionals pkgs.stdenv.isLinux [ gatekeeper ]);

        "site-env-orioledb-17" = makeSiteEnv "orioledb-17" (
          lib.optionals pkgs.stdenv.isLinux [ gatekeeper ]
        );
      };
    in
    {
      packages = siteEnvs;
      legacyPackages = siteEnvs;
    };
}
