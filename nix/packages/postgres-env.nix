{
  perSystem =
    {
      lib,
      pkgs,
      self',
      ...
    }:
    let
      # Make a bundle of packages, as a single derivation, to be installed into the
      # postgres user's nix profile, during image provisioning or instance update.
      debugPaths =
        version:
        lib.optionals pkgs.stdenv.isLinux [ self'.packages."postgresql_${version}_debug" ]
        # orioledb.so ships as a separate extension package (nix/ext/orioledb.nix), not
        # part of the postgresql derivation itself, so its debug output isn't covered by
        # postgresql_${version}_debug above and has to be pulled in explicitly.
        ++ lib.optionals (pkgs.stdenv.isLinux && version == "orioledb-17") [
          self'.legacyPackages."psql_${version}".exts.orioledb.debug
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

      realisePostgresDebug =
        version:
        pkgs.writeShellApplication {
          name = "realise-postgres-debug";
          text = ''
            nix-env --profile /nix/var/nix/profiles/postgres-debug --set "$(nix-store --realise ${builtins.unsafeDiscardStringContext (makePostgresEnvDebug version).outPath})"
          '';
        };

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
          ++ (
            if version == "orioledb-17" then
              [ self'.packages."postgresql_${version}_src" ] ++ debugPaths version
            else
              lib.optionals pkgs.stdenv.isLinux [ (realisePostgresDebug version) ]
          );
        };
    in
    {
      packages = {
        postgres-env-15 = makePostgresEnv "15";
        postgres-env-17 = makePostgresEnv "17";
        postgres-env-orioledb-17 = makePostgresEnv "orioledb-17";
        postgres-env-15-debug = makePostgresEnvDebug "15";
        postgres-env-17-debug = makePostgresEnvDebug "17";
      };
    };
}
