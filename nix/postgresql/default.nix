{
  self',
  pkgs,
  supportedPostgresVersions,
}:
let
  # Creates Postgres packages for a specific flavor (standard or orioledb)
  mkPostgresqlPackages =
    {
      namePrefix,
      jitSupport,
      supportedVersions,
    }:
    pkgs.lib.mapAttrs' (
      version: config:
      let
        versionSuffix = if jitSupport then "${version}_jit" else version;
      in
      pkgs.lib.nameValuePair "${namePrefix}${versionSuffix}" (
        pkgs.callPackage ./generic.nix {
          inherit (config) version hash;
          jitSupport = jitSupport;
          self = pkgs;
        }
      )
    ) supportedVersions;

  # Define Postgres flavors with their configuration
  postgresFlavors = [
    {
      namePrefix = "postgresql_";
      versions = supportedPostgresVersions.postgres;
    }
    {
      namePrefix = "postgresql_orioledb-";
      versions = supportedPostgresVersions.orioledb;
    }
  ];

  # Generate packages for all flavors with both JIT enabled and disabled
  mkAllPackages =
    flavors: jitSupport:
    pkgs.lib.foldl' (
      acc: flavor:
      acc
      // (mkPostgresqlPackages {
        inherit (flavor) namePrefix;
        inherit jitSupport;
        supportedVersions = flavor.versions;
      })
    ) { } flavors;

  # Generate source packages dynamically from supported versions
  mkSourcePackages =
    flavors:
    pkgs.lib.foldl' (
      acc: flavor:
      acc
      // (pkgs.lib.mapAttrs' (
        version: _:
        pkgs.lib.nameValuePair "${flavor.namePrefix}${version}_src" (
          pkgs.callPackage ./src.nix { postgresql = self'.packages."${flavor.namePrefix}${version}"; }
        )
      ) flavor.versions)
    ) { } flavors;

  # Generate debug packages dynamically from supported versions (Linux only)
  mkDebugPackages =
    flavors:
    pkgs.lib.foldl' (
      acc: flavor:
      acc
      // (pkgs.lib.mapAttrs' (
        version: _:
        pkgs.lib.nameValuePair "${flavor.namePrefix}${version}_debug" (
          self'.packages."${flavor.namePrefix}${version}".debug
        )
      ) flavor.versions)
    ) { } flavors;
in
# Combine all PostgreSQL packages: runtime packages + source packages + debug packages
(mkAllPackages postgresFlavors false)
// (mkAllPackages postgresFlavors true)
// (mkSourcePackages postgresFlavors)
// pkgs.lib.optionalAttrs (pkgs.stdenv.isLinux) (mkDebugPackages postgresFlavors)
