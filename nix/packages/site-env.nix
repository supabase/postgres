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

      # Given a git sha and a named env (e.g. site-env-17, postgres-env-17),
      # fetches its catalog entry and flips /nix/var/nix/profiles/<env> to it.
      # Generic across any single-package catalog entry named <env>-<system>.json.
      site-update = pkgs.writeShellApplication {
        name = "site-update";
        runtimeInputs = [
          pkgs.awscli2
          pkgs.jq
          pkgs.nix
        ];
        text = ''
          sha="''${1:?Usage: $0 <git-sha> <env>}"
          env="''${2:?Usage: $0 <git-sha> <env>}"
          system="$(uname -m)-linux"
          profile="/nix/var/nix/profiles/''${env}"

          catalog="''${SITE_UPDATE_CATALOG:-}"
          if [[ -z "$catalog" ]]; then
            catalog="/tmp/''${env}-catalog-''${sha}-''${system}.json"
            aws s3 cp "s3://supabase-internal-artifacts/nix-catalog/''${sha}-''${env}-''${system}.json" \
              "$catalog" --region ap-southeast-1
          fi

          path="$(jq -er --arg s "$system" '.[$s]' "$catalog")"
          [[ "$(basename "$path")" == *"-''${env}" ]] || {
            echo "error: resolved path $path is not tagged for env $env" >&2
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
