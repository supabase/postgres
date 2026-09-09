# These are envs (package sets per pg major version) deployed to instances
# at /nix/var/nix/profiles/site-<major> and updated regularly.
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

      # Given a git sha and pg major, fetches the site-env catalog entry
      site-update = pkgs.writeShellApplication {
        name = "site-update";
        runtimeInputs = [
          pkgs.awscli2
          pkgs.jq
          pkgs.nix
        ];
        text = ''
          sha="''${1:?Usage: $0 <git-sha> <major>}"
          major="''${2:?Usage: $0 <git-sha> <major>}"
          system="$(uname -m)-linux"
          profile="/nix/var/nix/profiles/site-''${major}"

          catalog="''${SITE_UPDATE_CATALOG:-}"
          if [[ -z "$catalog" ]]; then
            catalog="/tmp/site-env-catalog-''${sha}-''${major}-''${system}.json"
            aws s3 cp "s3://supabase-internal-artifacts/nix-catalog/''${sha}-site-env_''${major}-''${system}.json" \
              "$catalog" --region ap-southeast-1
          fi

          path="$(jq -er --arg s "$system" '.[$s]' "$catalog")"
          [[ "$(basename "$path")" == *"-site-env-''${major}" ]] || {
            echo "error: resolved path $path is not tagged for major $major" >&2
            exit 1
          }

          [[ "$(readlink -f "$profile")" == "$path" ]] && exit 0
          nix-store --realise --option stalled-download-timeout 120 "$path" >/dev/null
          nix-env --profile "$profile" --set "$path"
        '';
      };
    in
    {
      packages = siteEnvs // {
        inherit site-update;
      };
      legacyPackages = siteEnvs // {
        inherit site-update;
      };
    };
}
