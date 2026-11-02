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
      supportedVersions,
      isOrioleDB,
    }:
    pkgs.lib.mapAttrs' (
      version: config:
      pkgs.lib.nameValuePair "${namePrefix}${version}" (
        pkgs.callPackage ./generic.nix {
          inherit isOrioleDB;
          inherit (config) version hash revision;
          self = pkgs;
          portable = false; # Default to non-portable, can be overridden
        }
      )
    ) supportedVersions;

  # Define Postgres flavors with their configuration
  postgresFlavors = [
    {
      namePrefix = "postgresql_";
      versions = supportedPostgresVersions.postgres;
      isOrioleDB = false;
    }
    {
      namePrefix = "postgresql_orioledb-";
      versions = supportedPostgresVersions.orioledb;
      isOrioleDB = true;
    }
  ];

  # Generate packages for all flavors
  mkAllPackages =
    flavors:
    pkgs.lib.foldl' (
      acc: flavor:
      acc
      // (mkPostgresqlPackages {
        inherit (flavor) namePrefix isOrioleDB;
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
          let
            postgresql = self'.packages."${flavor.namePrefix}${version}";
          in
          if flavor.isOrioleDB then
            (pkgs.symlinkJoin {
              name = "${postgresql.name}-debug";
              paths = [
                postgresql.debug
                self'.legacyPackages."psql_orioledb-${version}".exts.orioledb.debug
                self'.packages."${flavor.namePrefix}${version}_src"
              ];
            }).overrideAttrs
              {
                allowSubstitutes = true;
                preferLocalBuild = false;
              }
          else
            postgresql.debug
        )
      ) flavor.versions)
    ) { } flavors;
in
# Combine all PostgreSQL packages: runtime packages + source packages + debug packages
(mkAllPackages postgresFlavors)
// (mkSourcePackages postgresFlavors)
// pkgs.lib.optionalAttrs (pkgs.stdenv.isLinux) (mkDebugPackages postgresFlavors)
