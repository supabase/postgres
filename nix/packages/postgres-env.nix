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

      extDebug =
        version:
        let
          exts = self'.legacyPackages."psql_${version}".exts;
        in
        lib.concatMap (e: e.passthru.debug) [
          exts.wrappers
          exts.pg_graphql
          exts.pg_jsonschema
        ];

      makePostgresEnvDebug =
        version:
        pkgs.symlinkJoin {
          name = "postgres-env-${version}-debug";
          paths = debugPaths version ++ lib.optionals pkgs.stdenv.isLinux (extDebug version);
        };

      debugProfile = "/nix/var/nix/profiles/postgres-debug";

      realisePostgresDebug =
        version:
        pkgs.writeShellApplication {
          name = "realise-postgres-debug";
          text = ''
            nix-env --profile ${debugProfile} --set "$(nix-store --realise ${builtins.unsafeDiscardStringContext (makePostgresEnvDebug version).outPath})"
          '';
        };

      cleanupPostgresDebug = pkgs.writeShellApplication {
        name = "cleanup-postgres-debug";
        text = ''
          rm -f ${debugProfile} ${debugProfile}-*-link
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
          ++ lib.optionals pkgs.stdenv.isLinux [
            (realisePostgresDebug version)
            cleanupPostgresDebug
          ];
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
