{ pkgs, supportedPostgresVersions }:
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
      let versionSuffix = if jitSupport then "${version}_jit" else version;
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
    { namePrefix = "postgresql_"; versions = supportedPostgresVersions.postgres; }
    { namePrefix = "postgresql_orioledb-"; versions = supportedPostgresVersions.orioledb; }
  ];

  # Generate packages for all flavors with both JIT enabled and disabled
  mkAllPackages = flavors: jitSupport:
    pkgs.lib.foldl' (acc: flavor:
      acc // (mkPostgresqlPackages {
        inherit (flavor) namePrefix;
        inherit jitSupport;
        supportedVersions = flavor.versions;
      })
    ) {} flavors;
in
# Combine packages with JIT disabled and enabled
(mkAllPackages postgresFlavors false) // (mkAllPackages postgresFlavors true)
