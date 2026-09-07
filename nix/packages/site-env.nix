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
      # Given a git sha, fetches the site-env catalog entry for this instance's pg
      # major and flips /nix/var/nix/profiles/site to it. Generic across majors.
      # Also baked into siteEnvs below so a freshly-baked AMI has it on PATH before
      # salt ever runs — salt itself always re-fetches its own copy from the
      # catalog rather than trusting whatever happens to be in the profile.
      site-env-update = pkgs.writeShellApplication {
        name = "site-env-update";
        runtimeInputs = [
          pkgs.awscli2
          pkgs.jq
        ];
        text = ''
          sha="''${1:?Usage: $0 <git-sha>}"
          system="$(uname -m)-linux"
          major="$(cut -d. -f1 /data/pgdata/PG_VERSION)"
          grep -q '^ORIOLEDB_ENABLED=true' /etc/environment.d/postgresql.env 2>/dev/null && major="orioledb-$major"

          catalog="/tmp/site-env-catalog-''${sha}-''${major}-''${system}.json"
          aws s3 cp "s3://supabase-internal-artifacts/nix-catalog/''${sha}-site-env_''${major}-''${system}.json" \
            "$catalog" --region ap-southeast-1

          path="$(jq -er --arg s "$system" '.[$s]' "$catalog")"
          nix-store -r --option stalled-download-timeout 120 "$path" >/dev/null
          nix-env --profile /nix/var/nix/profiles/site --set "$path"
        '';
      };

      makeSiteEnv =
        version: extraPaths:
        pkgs.buildEnv {
          name = "site-env-${version}";
          paths = [
            self'.legacyPackages."psql_${version}".exts.supautils
            site-env-update
          ] ++ extraPaths;
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
      packages = siteEnvs // { inherit site-env-update; };
      legacyPackages = siteEnvs // { inherit site-env-update; };
    };
}
