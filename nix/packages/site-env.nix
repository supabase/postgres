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
      # Scripts run on the host bash to keep Nix's bash and glibc out of the closure.
      writeHostBash =
        name: text:
        pkgs.writeTextFile {
          inherit name;
          executable = true;
          destination = "/bin/${name}";
          text = ''
            #!/usr/bin/env bash
            set -euo pipefail
            ${text}
          '';
          checkPhase = ''
            ${pkgs.shellcheck}/bin/shellcheck "$target"
          '';
        };

      makeSiteEnv =
        version: extraPaths:
        let
          supautils = self'.legacyPackages."psql_${version}".exts.supautils;
          # Site profile activation script. MUST STAY IDEMPOTENT!
          activate = writeHostBash "activate" ''
            echo "Activating site profile."
            echo "supautils at /nix/var/nix/profiles/site/lib/postgresql/supautils.so: picked up next session via session_preload_libraries, if dynamic_library_path includes /nix/var/nix/profiles/site/lib/postgresql."
            echo "Site profile activated."
          '';
        in
        pkgs.buildEnv {
          name = "site-env-${version}";
          paths = [
            supautils
            activate
          ]
          ++ extraPaths;
          passthru = { inherit activate; };
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
      packages = siteEnvs;
      legacyPackages = siteEnvs;
    };
}
