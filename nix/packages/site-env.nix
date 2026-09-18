# These are envs (package sets per pg major version) deployed to instances
# at /nix/var/nix/profiles/<env-name> and updated regularly.
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
        };

      siteEnvs = {

        "site-env-15" = makeSiteEnv "15" [ ];

        # gatekeeper is only available for pg 17+ on linux

        "site-env-17" = makeSiteEnv "17" (lib.optionals pkgs.stdenv.isLinux [ self'.packages.gatekeeper ]);

        "site-env-orioledb-17" = makeSiteEnv "orioledb-17" (
          lib.optionals pkgs.stdenv.isLinux [ self'.packages.gatekeeper ]
        );
      };

      # aws and nix come from the environment.
      update-profile = pkgs.writeShellApplication {
        name = "update-profile";
        text = ''
          profile_name="''${1:?Usage: $0 <profile> <path>}"
          path="''${2:?Usage: $0 <profile> <path>}"
          profile_path="/nix/var/nix/profiles/''${profile_name}"

          [[ "$(basename "$path")" == *"-''${profile_name}" ]] || {
            echo "error: resolved path $path is not tagged for profile $profile_name" >&2
            exit 1
          }

          [[ "$(readlink -f "$profile_path")" == "$path" ]] && exit 0
          nix-store --realise --option stalled-download-timeout 120 "$path" >/dev/null
          nix-env --profile "$profile_path" --set "$path"
        '';
      };

      # Updates whichever site-env-* profile is already active on this host.
      update-site = pkgs.writeShellApplication {
        name = "update-site";
        runtimeInputs = [
          pkgs.jq
          update-profile
        ];
        text = ''
          sha="''${1:?Usage: $0 <git-sha>}"
          system="$(uname -m)-linux"
          shopt -s nullglob
          candidates=(/nix/var/nix/profiles/site-env-*)
          profile_name="$(basename "''${candidates[0]:?no site-env-* profile found}")"
          catalog="/tmp/''${profile_name}-catalog-''${sha}-''${system}.json"

          aws s3 cp "s3://supabase-internal-artifacts/nix-catalog/''${sha}-''${profile_name}-''${system}.json" \
            "$catalog" --region ap-southeast-1
          path="$(jq -er --arg s "$system" '.[$s]' "$catalog")"

          update-profile "$profile_name" "$path"
        '';
      };
    in
    {
      packages = siteEnvs // {
        inherit update-profile update-site;
      };
      legacyPackages = siteEnvs // {
        inherit update-profile update-site;
      };
    };
}
