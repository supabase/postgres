# These are profiles (package sets per pg major version) deployed to instances 
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
      makeSiteProfile =
        version: extraPaths:
        pkgs.buildEnv {
          name = "site-profile-${version}";
          paths = [ self'.legacyPackages."psql_${version}".exts.supautils ] ++ extraPaths;
        };

      siteProfiles = {

        "site-profile-15" = makeSiteProfile "15" [ ];

        # gatekeeper is only available for pg 17+ on linux

        "site-profile-17" = makeSiteProfile "17" (
          lib.optionals pkgs.stdenv.isLinux [ self'.packages.gatekeeper ]
        );

        "site-profile-orioledb-17" = makeSiteProfile "orioledb-17" (
          lib.optionals pkgs.stdenv.isLinux [ self'.packages.gatekeeper ]
        );
      };
    in
    {
      legacyPackages = siteProfiles;
    };
}
