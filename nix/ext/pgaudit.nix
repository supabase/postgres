{
  lib,
  stdenv,
  buildEnv,
  fetchFromGitHub,
  libkrb5,
  openssl,
  postgresql,
}:
#adapted from https://github.com/NixOS/nixpkgs/blob/master/pkgs/servers/sql/postgresql/ext/pgaudit.nix
let
  pname = "pgaudit";
  # Load version configuration from external file
  allVersions = (builtins.fromJSON (builtins.readFile ./versions.json)).${pname};

  # Filter versions compatible with current PostgreSQL version (these get libraries)
  supportedVersions = lib.filterAttrs (
    _: value: builtins.elem (lib.versions.major postgresql.version) value.postgresql
  ) allVersions;

  # Derived version information
  # All versions sorted (for SQL migration files)
  allVersionsList = lib.naturalSort (lib.attrNames allVersions);
  # Supported versions sorted (for libraries)
  versions = lib.naturalSort (lib.attrNames supportedVersions);
  latestVersion = lib.last versions;
  numberOfVersions = builtins.length versions;

  # Build packages only for supported versions (with libraries)
  packages = builtins.attrValues (
    lib.mapAttrs (name: value: build name value.hash) supportedVersions
  );

  # Helper function to generate migration SQL file pairs
  # Returns a list of {from, to} pairs for sequential migrations
  generateMigrationPairs =
    versions:
    let
      indexed = lib.imap0 (i: v: {
        idx = i;
        version = v;
      }) versions;
      pairs = lib.filter (x: x.idx > 0) indexed;
    in
    map (curr: {
      from = (lib.elemAt versions (curr.idx - 1));
      to = curr.version;
    }) pairs;

  # All migration pairs across all versions (sequential)
  allMigrationPairs = generateMigrationPairs allVersionsList;

  # Get the first supported version for this PG major
  firstSupportedVersion = lib.head versions;

  # Generate bridge migrations from unsupported versions to first supported version
  # These are needed when upgrading PostgreSQL major versions
  # Only include versions that come BEFORE the first supported version (no backwards migrations)
  unsupportedVersions = lib.filter (
    v: !(builtins.elem v versions) && (lib.versionOlder v firstSupportedVersion)
  ) allVersionsList;
  bridgeMigrations = map (v: {
    from = v;
    to = firstSupportedVersion;
  }) unsupportedVersions;

  # Build function for individual pgaudit versions
  build =
    version: hash:
    stdenv.mkDerivation {
      inherit pname version;

      src = fetchFromGitHub {
        owner = "pgaudit";
        repo = "pgaudit";
        rev = version;
        inherit hash;
      };

      buildInputs = [
        libkrb5
        openssl
        postgresql
      ];

      makeFlags = [ "USE_PGXS=1" ];

      postBuild =
        lib.optionalString (version == "1.7.0") ''
          mv ${pname}--1.7.sql ${pname}--1.7.0.sql
          cp ${pname}--1.7.0.sql ${pname}--1.6.1--1.7.0.sql
        ''
        + lib.optionalString (version == "1.7.1") ''
          mv ${pname}--1.7--1.7.1.sql ${pname}--1.7.0--1.7.1.sql
        '';

      installPhase = ''
        runHook preInstall

        mkdir -p $out/{lib,share/postgresql/extension}

        # Install shared library with version suffix
        mv ${pname}${postgresql.dlSuffix} $out/lib/${pname}-${version}${postgresql.dlSuffix}

        # Install SQL files with modifications
        sed -i '1s/^/DROP EVENT TRIGGER IF EXISTS pgaudit_ddl_command_end; \n/' *.sql
        sed -i '1s/^/DROP EVENT TRIGGER IF EXISTS pgaudit_sql_drop; \n/' *.sql
        sed -i 's/CREATE FUNCTION/CREATE OR REPLACE FUNCTION/' *.sql
        cp *.sql $out/share/postgresql/extension

        # Create version-specific control file pointing to versioned library
        sed -e "/^default_version =/d" \
            -e "s|^module_pathname = .*|module_pathname = '\$libdir/${pname}'|" \
          ${pname}.control > $out/share/postgresql/extension/${pname}--${version}.control

        runHook postInstall
      '';

      meta = with lib; {
        description = "Open Source PostgreSQL Audit Logging";
        homepage = "https://github.com/pgaudit/pgaudit";
        changelog = "https://github.com/pgaudit/pgaudit/releases/tag/${source.version}";
        license = licenses.postgresql;
        inherit (postgresql.meta) platforms;
      };
    };
in
buildEnv {
  name = pname;
  paths = packages;
  pathsToLink = [
    "/lib"
    "/share/postgresql/extension"
  ];
  postBuild = ''
    # Create symlinks to latest version for library and control file
    ln -sfn ${pname}-${latestVersion}${postgresql.dlSuffix} $out/lib/${pname}${postgresql.dlSuffix}

    # Create default control file pointing to latest
    {
      echo "default_version = '${latestVersion}'"
      cat $out/share/postgresql/extension/${pname}--${latestVersion}.control
    } > $out/share/postgresql/extension/${pname}.control

    # Generate cross-version migration SQL files
    # For each migration pair, if the target version's base SQL exists but we haven't
    # built that version (no library), we need to create migration files to bridge from
    # older versions to the first available version on this PG major
    ${lib.concatMapStringsSep "\n" (pair: ''
      # Check if we need to create migration ${pair.from}--${pair.to}.sql
      if [[ ! -f "$out/share/postgresql/extension/${pname}--${pair.from}--${pair.to}.sql" ]]; then
        # If the target SQL file exists, create the migration by copying it
        if [[ -f "$out/share/postgresql/extension/${pname}--${pair.to}.sql" ]]; then
          cp "$out/share/postgresql/extension/${pname}--${pair.to}.sql" \
             "$out/share/postgresql/extension/${pname}--${pair.from}--${pair.to}.sql"
        fi
      fi
    '') allMigrationPairs}

    # Generate bridge migrations from unsupported versions to first supported version
    # This handles cross-PostgreSQL-major-version upgrades
    ${lib.concatMapStringsSep "\n" (pair: ''
      # Create bridge migration ${pair.from}--${pair.to}.sql if not already present
      if [[ ! -f "$out/share/postgresql/extension/${pname}--${pair.from}--${pair.to}.sql" ]]; then
        # The bridge migration is just a copy of the target version's base SQL
        if [[ -f "$out/share/postgresql/extension/${pname}--${pair.to}.sql" ]]; then
          cp "$out/share/postgresql/extension/${pname}--${pair.to}.sql" \
             "$out/share/postgresql/extension/${pname}--${pair.from}--${pair.to}.sql"
        fi
      fi
    '') bridgeMigrations}

    # Verify all expected library files are present (one per version + symlink)
    expectedFiles=${toString (numberOfVersions + 1)}
    actualFiles=$(ls -A $out/lib/${pname}*${postgresql.dlSuffix} | wc -l)

    if [[ "$actualFiles" != "$expectedFiles" ]]; then
      echo "Error: Expected $expectedFiles library files, found $actualFiles"
      echo "Files found:"
      ls -la $out/lib/${pname}*${postgresql.dlSuffix} || true
      exit 1
    fi
  '';

  passthru = {
    inherit versions numberOfVersions;
    pname = "${pname}-all";
    version =
      "multi-" + lib.concatStringsSep "-" (map (v: lib.replaceStrings [ "." ] [ "-" ] v) versions);
    defaultSettings = {
      shared_preload_libraries = "pgaudit";
    };
  };
}
