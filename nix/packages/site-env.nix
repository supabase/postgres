# These are envs (package sets per pg major version) deployed to instances
# at /nix/var/nix/profiles/site and updated regularly.
{
  perSystem =
    {
      self',
      pkgs-pg17,
      lib,
      ...
    }:
    let
      makeSiteEnv =
        version: extraPaths:
        pkgs-pg17.buildEnv {
          name = "site-env-${version}";
          paths = [ self'.legacyPackages."psql_${version}".exts.supautils ] ++ extraPaths;
        };

      siteEnvs = {

        "site-env-15" = makeSiteEnv "15" [ ];

        # gatekeeper is only available for pg 17+ on linux

        "site-env-17" = makeSiteEnv "17" (
          lib.optionals pkgs-pg17.stdenv.isLinux [ self'.packages.gatekeeper ]
        );

        "site-env-orioledb-17" = makeSiteEnv "orioledb-17" (
          lib.optionals pkgs-pg17.stdenv.isLinux [ self'.packages.gatekeeper ]
        );
      };
    in
    {
      packages = siteEnvs;
      legacyPackages = siteEnvs;
    };
}
