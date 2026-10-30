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
      makeSiteEnv =
        version: extraPaths:
        let
          supautils = self'.legacyPackages."psql_${version}".exts.supautils;
          # Site profile activation script. MUST STAY IDEMPOTENT!
          activate = pkgs.writeTextFile {
            name = "activate";
            executable = true;
            destination = "/bin/activate";
            # Runs on the host bash to keep Nix's bash and glibc out of the closure.
            text = ''
              #!/usr/bin/env bash
              set -euo pipefail
              echo "Activating site profile."
              echo "Configured in /etc/postgresql/postgresql.conf (runtime could differ):"
              for guc in dynamic_library_path session_preload_libraries; do
                grep -h "^$guc" /etc/postgresql/postgresql.conf 2>/dev/null || echo "$guc is not set"
              done
              echo "Site profile activated."
            '';
            checkPhase = ''
              ${pkgs.shellcheck}/bin/shellcheck "$target"
            '';
          };
        in
        pkgs.buildEnv {
          name = "site-env-${version}";
          paths = [
            supautils
            activate
            self'.packages.postgres-collation-refresh
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
