{
  lib,
  stdenv,
  fetchFromGitHub,
  postgresql,
}:

let
  pname = "pg_cron";
  allVersions = (builtins.fromJSON (builtins.readFile ../versions.json)).${pname};
  supportedVersions = lib.filterAttrs (
    _: value: builtins.elem (lib.versions.major postgresql.version) value.postgresql
  ) allVersions;
  versions = lib.naturalSort (lib.attrNames supportedVersions);
  latestVersion = lib.last versions;
  numberOfVersions = builtins.length versions;
  build =
    version: versionData:
    stdenv.mkDerivation rec {
      inherit pname version;

      buildInputs = [ postgresql ];

      src = fetchFromGitHub {
        owner = "citusdata";
        repo = pname;
        rev = versionData.rev or "v${version}";
        hash = versionData.hash;
      };

      patches = map (p: ./. + "/${p}") (versionData.patches or [ ]);

      buildPhase = ''
        make PG_CONFIG=${postgresql}/bin/pg_config

        # Create version-specific SQL file
        cp pg_cron.sql pg_cron--${version}.sql

        # Create versioned control file with modified module path
        sed -e "/^default_version =/d" \
            -e "s|^module_pathname = .*|module_pathname = '\$libdir/pg_cron'|" \
            pg_cron.control > pg_cron--${version}.control
      '';

      installPhase = ''
        mkdir -p $out/{lib,share/postgresql/extension}

        # Install versioned library
        install -Dm755 ${pname}${postgresql.dlSuffix} $out/lib/${pname}-${version}${postgresql.dlSuffix}

        # Install version-specific files
        install -Dm644 ${pname}--${version}.sql $out/share/postgresql/extension/
        install -Dm644 ${pname}--${version}.control $out/share/postgresql/extension/

        # Install upgrade scripts
        find . -name 'pg_cron--*--*.sql' -exec install -Dm644 {} $out/share/postgresql/extension/ \;

        # For the latest version, create default control file and symlink
        if [[ "${version}" == "${latestVersion}" ]]; then
          {
            echo "default_version = '${version}'"
            cat $out/share/postgresql/extension/${pname}--${version}.control
          } > $out/share/postgresql/extension/${pname}.control
          ln -sfn ${pname}-${version}${postgresql.dlSuffix} $out/lib/${pname}${postgresql.dlSuffix}
        fi
      '';

      meta = with lib; {
        description = "Run Cron jobs through PostgreSQL";
        homepage = "https://github.com/citusdata/pg_cron";
        changelog = "https://github.com/citusdata/pg_cron/raw/v${version}/CHANGELOG.md";
        platforms = postgresql.meta.platforms;
        license = licenses.postgresql;
      };
    };
  packages = builtins.attrValues (lib.mapAttrs (name: value: build name value) supportedVersions);
in
stdenv.mkDerivation {
  pname = "${pname}-all";
  version =
    "multi-" + lib.concatStringsSep "-" (map (v: lib.replaceStrings [ "." ] [ "-" ] v) versions);

  buildInputs = packages;

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    mkdir -p $out/{lib,share/postgresql/extension,bin}

    # Install all versions
    for drv in ${lib.concatStringsSep " " packages}; do
      ln -sv $drv/lib/* $out/lib/
      cp -v --no-clobber $drv/share/postgresql/extension/* $out/share/postgresql/extension/ || true
    done

    # Find latest version
    latest_control=$(ls -v $out/share/postgresql/extension/${pname}--*.control | tail -n1)
    latest_version=$(basename "$latest_control" | sed -E 's/${pname}--([0-9.]+).control/\1/')

    # Create main control file only if it doesn't exist
    if [ ! -f "$out/share/postgresql/extension/${pname}.control" ]; then
      # Create main control file with default_version
      echo "default_version = '$latest_version'" > $out/share/postgresql/extension/${pname}.control
      cat "$latest_control" >> $out/share/postgresql/extension/${pname}.control
    fi

    # Library symlink - only if it doesn't exist
    if [ ! -f "$out/lib/${pname}${postgresql.dlSuffix}" ]; then
      ln -sfnv ${pname}-$latest_version${postgresql.dlSuffix} $out/lib/${pname}${postgresql.dlSuffix}
    fi

    # Create version switcher script
    cat > $out/bin/switch_pg_cron_version <<'EOF'
    #!/bin/sh
    set -e

    if [ $# -ne 1 ]; then
      echo "Usage: $0 <version>"
      echo "Example: $0 1.4.2"
      exit 1
    fi

    VERSION=$1
    NIX_PROFILE="/var/lib/postgresql/.nix-profile"

    # Follow the complete chain of symlinks to find the multi-version directory
    CURRENT_LINK="$NIX_PROFILE/lib/pg_cron-$VERSION${postgresql.dlSuffix}"
    echo "Starting with link: $CURRENT_LINK"

    # Follow first two symlinks to get to the multi-version directory
    for i in 1 2; do
        if [ -L "$CURRENT_LINK" ]; then
            NEXT_LINK=$(readlink "$CURRENT_LINK")
            echo "Following link: $NEXT_LINK"
            if echo "$NEXT_LINK" | grep -q '^/'; then
                CURRENT_LINK="$NEXT_LINK"
            else
                CURRENT_LINK="$(dirname "$CURRENT_LINK")/$NEXT_LINK"
            fi
            echo "Current link is now: $CURRENT_LINK"
        fi
    done

    # The multi-version directory should be the parent of the current link
    MULTI_VERSION_DIR=$(dirname "$CURRENT_LINK")
    echo "Found multi-version directory: $MULTI_VERSION_DIR"
    LIB_DIR="$MULTI_VERSION_DIR"
    EXTENSION_DIR="$NIX_PROFILE/share/postgresql/extension"

    echo "Looking for file: $LIB_DIR/pg_cron-$VERSION${postgresql.dlSuffix}"
    ls -la "$LIB_DIR" || true

    # Check if version exists
    if [ ! -f "$LIB_DIR/pg_cron-$VERSION${postgresql.dlSuffix}" ]; then
      echo "Error: Version $VERSION not found"
      exit 1
    fi

    # Update library symlink
    ln -sfnv "pg_cron-$VERSION${postgresql.dlSuffix}" "$LIB_DIR/pg_cron${postgresql.dlSuffix}"

    # Update control file
    echo "default_version = '$VERSION'" > "$EXTENSION_DIR/pg_cron.control"
    cat "$EXTENSION_DIR/pg_cron--$VERSION.control" >> "$EXTENSION_DIR/pg_cron.control"

    echo "Successfully switched pg_cron to version $VERSION"
    EOF

    chmod +x $out/bin/switch_pg_cron_version
  '';

  passthru = {
    inherit versions numberOfVersions;
  };

  meta = with lib; {
    description = "Run Cron jobs through PostgreSQL (multi-version compatible)";
    homepage = "https://github.com/citusdata/pg_cron";
    platforms = postgresql.meta.platforms;
    license = licenses.postgresql;
  };
}
