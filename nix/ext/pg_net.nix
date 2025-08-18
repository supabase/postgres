{
  pkgs,
  lib,
  stdenv,
  fetchFromGitHub,
  curl,
  postgresql,
  libuv,
  writeShellApplication,
}:

let
  switchPgNetVersion = writeShellApplication {
    name = "switch_pg_net_version";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      # Create version switcher script
      set -e

      if [ $# -ne 1 ]; then
        echo "Usage: $0 <version>"
        echo "Example: $0 0.10.0"
        echo ""
        echo "Optional environment variables:"
        echo "  NIX_PROFILE - Path to nix profile (default: /var/lib/postgresql/.nix-profile)"
        echo "  LIB_DIR - Override library directory"
        echo "  EXTENSION_DIR - Override extension directory"
        exit 1
      fi

      VERSION=$1

      # Set defaults, allow environment variable overrides
      : ''${NIX_PROFILE:="/var/lib/postgresql/.nix-profile"}
      : ''${LIB_DIR:=""}
      : ''${EXTENSION_DIR:=""}

      # If LIB_DIR not explicitly set, auto-detect it
      if [ -z "$LIB_DIR" ]; then
        # Follow the complete chain of symlinks to find the multi-version directory
        CURRENT_LINK="$NIX_PROFILE/lib/pg_net-$VERSION${postgresql.dlSuffix}"
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
      else
        echo "Using provided LIB_DIR: $LIB_DIR"
      fi

      # If EXTENSION_DIR not explicitly set, use default
      if [ -z "$EXTENSION_DIR" ]; then
        EXTENSION_DIR="$NIX_PROFILE/share/postgresql/extension"
      fi
      echo "Using EXTENSION_DIR: $EXTENSION_DIR"

      echo "Looking for file: $LIB_DIR/pg_net-$VERSION${postgresql.dlSuffix}"
      ls -la "$LIB_DIR" || true

      # Check if version exists
      if [ ! -f "$LIB_DIR/pg_net-$VERSION${postgresql.dlSuffix}" ]; then
        echo "Error: Version $VERSION not found in $LIB_DIR"
        echo "Available versions:"
        ls "$LIB_DIR"/pg_net-*${postgresql.dlSuffix} 2>/dev/null | sed 's/.*pg_net-/  /' | sed 's/${postgresql.dlSuffix}$//' || echo "  No versions found"
        exit 1
      fi

      # Update library symlink
      ln -sfnv "pg_net-$VERSION${postgresql.dlSuffix}" "$LIB_DIR/pg_net${postgresql.dlSuffix}"

      # Update control file
      echo "default_version = '$VERSION'" > "$EXTENSION_DIR/pg_net.control"
      cat "$EXTENSION_DIR/pg_net--$VERSION.control" >> "$EXTENSION_DIR/pg_net.control"

      echo "Successfully switched pg_net to version $VERSION"
      EOF
    '';
  };
  pname = "pg_net";
  build =
    version: hash:
    stdenv.mkDerivation rec {
      inherit pname version;

      buildInputs = [
        curl
        postgresql
      ]
      ++ lib.optional (version == "0.6") libuv;

      src = fetchFromGitHub {
        owner = "supabase";
        repo = pname;
        rev = "refs/tags/v${version}";
        inherit hash;
      };

      buildPhase = ''
        make PG_CONFIG=${postgresql}/bin/pg_config
      '';

      postPatch =
        lib.optionalString (version == "0.6") ''
          # handle collision with pg_net 0.10.0
          rm sql/pg_net--0.2--0.3.sql
          rm sql/pg_net--0.4--0.5.sql
          rm sql/pg_net--0.5.1--0.6.sql
        ''
        + lib.optionalString (version == "0.7.1") ''
          # handle collision with pg_net 0.10.0
          rm sql/pg_net--0.5.1--0.6.sql
        '';

      env.NIX_CFLAGS_COMPILE = "-Wno-error";

      installPhase = ''
        mkdir -p $out/{lib,share/postgresql/extension}

        # Install versioned library
        install -Dm755 ${pname}${postgresql.dlSuffix} $out/lib/${pname}-${version}${postgresql.dlSuffix}

        if [ -f sql/${pname}.sql ]; then
          cp sql/${pname}.sql $out/share/postgresql/extension/${pname}--${version}.sql
        else
          cp sql/${pname}--${version}.sql $out/share/postgresql/extension/${pname}--${version}.sql
        fi

        # Install upgrade scripts
        find . -name '${pname}--*--*.sql' -exec install -Dm644 {} $out/share/postgresql/extension/ \;

        # Create versioned control file with modified module path
        sed -e "/^default_version =/d" \
            -e "s|^module_pathname = .*|module_pathname = '\$libdir/${pname}'|" \
          ${pname}.control > $out/share/postgresql/extension/${pname}--${version}.control
      '';

      meta = with lib; {
        description = "Async networking for Postgres";
        homepage = "https://github.com/supabase/pg_net";
        platforms = postgresql.meta.platforms;
        license = licenses.postgresql;
      };
    };
  allVersions = (builtins.fromJSON (builtins.readFile ./versions.json)).pg_net;
  # Filter out versions that don't work on current platform
  platformFilteredVersions = lib.filterAttrs (
    name: _:
    # Exclude 0.11.0 on macOS due to epoll.h dependency
    !(stdenv.isDarwin && name == "0.11.0")
  ) allVersions;
  supportedVersions = lib.filterAttrs (
    _: value: builtins.elem (lib.versions.major postgresql.version) value.postgresql
  ) platformFilteredVersions;
  versions = lib.naturalSort (lib.attrNames supportedVersions);
  latestVersion = lib.last versions;
  numberOfVersions = builtins.length versions;
  packages = builtins.attrValues (
    lib.mapAttrs (name: value: build name value.hash) supportedVersions
  );
in
pkgs.buildEnv {
  name = pname;
  paths = packages ++ [ switchPgNetVersion ];
  postBuild = ''
    {
      echo "default_version = '${latestVersion}'"
      cat $out/share/postgresql/extension/${pname}--${latestVersion}.control
    } > $out/share/postgresql/extension/${pname}.control
    ln -sfn ${pname}-${latestVersion}${postgresql.dlSuffix} $out/lib/${pname}${postgresql.dlSuffix}


    # checks
    (set -x
       test "$(ls -A $out/lib/${pname}*${postgresql.dlSuffix} | wc -l)" = "${
         toString (numberOfVersions + 1)
       }"
    )
  '';

  passthru = {
    inherit versions numberOfVersions;
    pname = "${pname}-all";
    version =
      "multi-" + lib.concatStringsSep "-" (map (v: lib.replaceStrings [ "." ] [ "-" ] v) versions);
  };
}
