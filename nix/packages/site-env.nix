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

      # Given a profile name (e.g. site-env-17, postgres-env-17) and a git sha,
      # fetches that name's catalog entry and flips /nix/var/nix/profiles/<name>
      # to it. Generic across any single-package catalog entry named <name>-<system>.json.
      # Assumes `aws` is provided by the environment (AMIs already install AWS CLI v2).
      update-profile = pkgs.writeShellApplication {
        name = "update-profile";
        runtimeInputs = [
          pkgs.jq
          pkgs.nix
        ];
        text = ''
          profile_name="''${1:?Usage: $0 <profile> <git-sha>}"
          system="$(uname -m)-linux"
          profile_path="/nix/var/nix/profiles/''${profile_name}"

          catalog="''${UPDATE_PROFILE_CATALOG:-}"
          if [[ -z "$catalog" ]]; then
            sha="''${2:?Usage: $0 <profile> <git-sha>}"
            catalog="/tmp/''${profile_name}-catalog-''${sha}-''${system}.json"
            aws s3 cp "s3://supabase-internal-artifacts/nix-catalog/''${sha}-''${profile_name}-''${system}.json" \
              "$catalog" --region ap-southeast-1
          fi

          path="$(jq -er --arg s "$system" '.[$s]' "$catalog")"
          [[ "$(basename "$path")" == *"-''${profile_name}" ]] || {
            echo "error: resolved path $path is not tagged for profile $profile_name" >&2
            exit 1
          }

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
