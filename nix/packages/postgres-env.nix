{
  perSystem =
    {
      lib,
      pkgs,
      self',
      ...
    }:
    let
      debugPaths =
        version:
        lib.optionals pkgs.stdenv.isLinux [ self'.packages."postgresql_${version}_debug" ]
        ++ lib.optionals (pkgs.stdenv.isLinux && version == "orioledb-17") [
          self'.legacyPackages."psql_${version}".exts.orioledb.debug
          self'.packages."postgresql_${version}_src"
        ];

      makePostgresEnvDebug =
        version:
        (pkgs.symlinkJoin {
          name = "postgres-env-${version}-debug";
          paths = debugPaths version;
        }).overrideAttrs
          {
            allowSubstitutes = true;
            preferLocalBuild = false;
          };

      # First line: the debug env's store path. Then "<bytes> <path>" for each
      # path in its closure, so realise-postgres-debug can tell how much it is
      # about to add to the disk. Bytes are the NAR size plus a 4KiB block per
      # file/dir, since the source tree is thousands of small files. References
      # are discarded so that this doesn't pull the debug env in.
      debugEnvManifest =
        version:
        pkgs.runCommand "postgres-debug-env-manifest"
          {
            debugEnv = makePostgresEnvDebug version;
            exportReferencesGraph.closure = [ (makePostgresEnvDebug version) ];
            __structuredAttrs = true;
            unsafeDiscardReferences.out = true;
            nativeBuildInputs = [ pkgs.jq ];
          }
          ''
            echo "$debugEnv" > $out
            jq -r '.closure[] | "\(.narSize) \(.path)"' "$NIX_ATTRS_JSON_FILE" |
              while read -r size path; do
                echo "$((size + 4096 * $(find "$path" | wc -l))) $path"
              done >> $out
          '';

      realisePostgresDebug =
        version:
        pkgs.writeShellApplication {
          name = "realise-postgres-debug";
          runtimeInputs = [ pkgs.coreutils ];
          # Called from orioledb-coredump.service, whose PATH doesn't include
          # nix. NIX_REMOTE=daemon makes root go through the daemon too, since
          # that unit's ProtectSystem=strict leaves /nix read-only.
          #
          # Exits 3 without downloading anything if the download would leave
          # less than POSTGRES_DEBUG_RESERVE_BYTES (default 1GiB) free.
          text = ''
            manifest=${debugEnvManifest version}
            debug_env=$(head -n 1 "$manifest")
            reserve=''${POSTGRES_DEBUG_RESERVE_BYTES:-1073741824}

            needed=0
            while read -r size path; do
              [ -e "$path" ] || needed=$((needed + size))
            done < <(tail -n +2 "$manifest")
            if [ "$needed" -gt 0 ]; then
              avail=$(df --output=avail -B1 /nix/store | tail -n 1 | tr -d ' ')
              if [ $((avail - needed)) -lt "$reserve" ]; then
                echo "realise-postgres-debug: not enough space on /nix/store: needs $needed bytes, $avail available, $reserve must stay free" >&2
                exit 3
              fi
            fi

            nix_store=/nix/var/nix/profiles/default/bin/nix-store
            [ -x "$nix_store" ] || nix_store=nix-store
            NIX_REMOTE=daemon "$nix_store" --realise "$debug_env"
          '';
        };

      # Make a bundle of packages, as a single derivation, to be installed into the
      # postgres user's nix profile, during image provisioning or instance update.
      makePostgresEnv =
        version:
        pkgs.symlinkJoin {
          name = "postgres-env-${version}";
          paths = [
            self'.packages."psql_${version}/bin"
            self'.packages.pg_prove
            self'.packages.supabase-groonga
          ]
          ++ lib.optionals (pkgs.stdenv.isLinux && version != "15") [ self'.packages.gatekeeper ]
          ++ lib.optionals pkgs.stdenv.isLinux [ (realisePostgresDebug version) ]
          ++ lib.optionals (pkgs.stdenv.isLinux && version == "orioledb-17") [
            (makePostgresEnvDebug version)
          ];
          passthru = lib.optionalAttrs pkgs.stdenv.isLinux {
            realise-postgres-debug = realisePostgresDebug version;
          };
        };
    in
    {
      packages = {
        postgres-env-15 = makePostgresEnv "15";
        postgres-env-17 = makePostgresEnv "17";
        postgres-env-orioledb-17 = makePostgresEnv "orioledb-17";
        postgres-env-15-debug = makePostgresEnvDebug "15";
        postgres-env-17-debug = makePostgresEnvDebug "17";
        postgres-env-orioledb-17-debug = makePostgresEnvDebug "orioledb-17";
      };
    };
}
