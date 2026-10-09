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
      # Prunes old site, postgres, and default profile generations, then runs nix-store --gc in a throttled transient systemd unit.
      site-nix-gc = pkgs.writeShellApplication {
        name = "site-nix-gc";
        text = ''
          /nix/var/nix/profiles/default/bin/nix-env --profile /nix/var/nix/profiles/site --delete-generations +3
          /nix/var/nix/profiles/default/bin/nix-env --profile /nix/var/nix/profiles/default --delete-generations +2
          if [[ -L /var/lib/postgresql/.nix-profile ]]; then
            /nix/var/nix/profiles/default/bin/nix-env --profile "$(readlink /var/lib/postgresql/.nix-profile)" --delete-generations +2
          fi
          if [[ ! -d /run/systemd/system ]]; then
            echo "Systemd not found. Skipping nix-store --gc."
            exit 0
          fi
          if systemctl is-active --quiet site-nix-gc; then
            echo "Garbage collection already running. Skipping nix-store --gc."
            exit 0
          fi
          systemd-run \
            --unit=site-nix-gc --collect --no-block --setenv=NIX_REMOTE=local \
            -p Nice=19 -p CPUSchedulingPolicy=idle -p CPUQuota=20% \
            -p IOSchedulingClass=idle -p IOWeight=1 -p IOWriteBandwidthMax="/nix 20M" \
            -p MemoryHigh=10% -p MemoryMax=15% -p OOMScoreAdjust=1000 \
            -p RuntimeMaxSec=2h \
            /nix/var/nix/profiles/default/bin/nix-store --gc --max-freed 2G \
            || echo "systemd-run failed. Skipping nix-store --gc."
        '';
      };

      makeSiteEnv =
        version: extraPaths:
        let
          supautils = self'.legacyPackages."psql_${version}".exts.supautils;
          # Site profile activation script. MUST STAY IDEMPOTENT!
          activate = pkgs.writeShellApplication {
            name = "activate";
            text = ''
              echo "Activating site profile."
              echo "supautils at /nix/var/nix/profiles/site/pg-extensions/supautils.so: picked up next session via session_preload_libraries, if dynamic_library_path includes /nix/var/nix/profiles/site/pg-extensions."
              ${lib.optionalString (extraPaths != [ ]) ''
                echo "gatekeeper at /nix/var/nix/profiles/site/lib/security/pam_jit_pg.so: loaded by PAM if linked from ${pkgs.pam}/lib/security/pam_jit_pg.so."
              ''}
              echo "Site profile activated."
            '';
          };
        in
        pkgs.buildEnv {
          name = "site-env-${version}";
          paths = [
            supautils
            activate
            site-nix-gc
          ]
          ++ extraPaths;
          passthru = { inherit activate site-nix-gc; };
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
