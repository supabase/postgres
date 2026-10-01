# These are envs (package sets per pg major version) deployed to instances
{
  perSystem =
    {
      self',
      pkgs,
      lib,
      ...
    }:
    let
      makeSiteEnv =
        version: extraPaths:
        pkgs.buildEnv {
          name = "site-env-${version}";
          paths = [ self'.legacyPackages."psql_${version}".exts.supautils ] ++ extraPaths;
          postBuild = ''
            echo site-env-${version} > $out/site-env-name
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

      # Set the named nix profile to the provided nix store path.
      # aws and nix come from the environment.
      update-profile = pkgs.writeShellApplication {
        name = "update-profile";
        text = ''
          profile_name="''${1:?Usage: $0 <profile> <path>}"
          path="''${2:?Usage: $0 <profile> <path>}"
          profile_path="/nix/var/nix/profiles/''${profile_name}"

          [[ "$(readlink -f "$profile_path")" == "$path" ]] && exit 0
          nix-store --realise --option stalled-download-timeout 120 "$path" >/dev/null
          nix-env --profile "$profile_path" --set "$path"
        '';
      };

    in
    {
      packages = siteEnvs // {
        inherit update-profile;
      };
      legacyPackages = siteEnvs // {
        inherit update-profile;
      };
    };
}
