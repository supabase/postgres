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

      # Prunes old generations, then runs nix-store --gc. Throttled by a transient systemd unit, or by nice and ionice without systemd.
      site-nix-gc = writeHostBash "site-nix-gc" ''
        prune() { nix-env --profile "$1" --delete-generations +2; }
        prune /nix/var/nix/profiles/site
        prune /nix/var/nix/profiles/default
        if [[ -L /var/lib/postgresql/.nix-profile ]]; then
          prune "$(readlink /var/lib/postgresql/.nix-profile)"
        fi

        export NIX_REMOTE=local
        gc=("$(command -v nix-store)" --gc --quiet)

        if [[ -d /run/systemd/system ]]; then
          if systemctl is-active --quiet site-nix-gc; then
            echo "Garbage collection already running."
            exit 0
          fi
          systemd-run \
            --unit=site-nix-gc --collect --no-block --setenv=NIX_REMOTE=local \
            -p Nice=19 -p CPUSchedulingPolicy=idle -p CPUQuota=20% \
            -p IOSchedulingClass=idle -p IOWeight=1 -p IOWriteBandwidthMax="/nix 20M" \
            -p MemoryHigh=10% -p MemoryMax=15% -p OOMScoreAdjust=1000 \
            -p RuntimeMaxSec=2h \
            "''${gc[@]}" && exit 0
          echo "systemd-run failed. Running in the foreground."
        fi

        throttle=(nice -n 19)
        command -v ionice >/dev/null && throttle+=(ionice -c 3)
        exec "''${throttle[@]}" "''${gc[@]}"
      '';

      makeSiteEnv =
        version: extraPaths:
        let
          supautils = self'.legacyPackages."psql_${version}".exts.supautils;
          # Site profile activation script. MUST STAY IDEMPOTENT!
          activate = writeHostBash "activate" ''
            echo "Activating site profile."
            echo "Configured in /etc/postgresql/postgresql.conf (runtime could differ):"
            for guc in dynamic_library_path session_preload_libraries; do
              grep -h "^$guc" /etc/postgresql/postgresql.conf 2>/dev/null || echo "$guc is not set"
            done
            echo "Site profile activated."
          '';
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
