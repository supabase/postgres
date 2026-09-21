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
          postBuild = "echo site-env-${version} > $out/site-env-name";
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

      # Fetch catalog and update site profile from given postgres repo hash.
      # aws and nix come from the environment.
      update-site = pkgs.writeShellApplication {
        name = "update-site";
        runtimeInputs = [ update-profile ];
        text = ''
          sha="''${1:?Usage: $0 <git-sha>}"
          system="$(uname -m)-linux"
          variant="$(cat /nix/var/nix/profiles/site/site-env-name)"
          catalog="/tmp/''${variant}-catalog-''${sha}-''${system}"

          aws s3 cp "s3://supabase-internal-artifacts/nix-catalog/''${sha}-''${variant}-''${system}" \
            "$catalog" --region ap-southeast-1
          path="$(cat "$catalog")"

          update-profile site "$path"
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
