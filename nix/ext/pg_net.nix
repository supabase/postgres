{
  pkgs,
  lib,
  stdenv,
  fetchFromGitHub,
  curl,
  postgresql,
  libuv,
  writeShellApplication,
  makeWrapper,
}:

let
  enableOverlayOnPackage = writeShellApplication {
    name = "enable_overlay_on_package";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      # This script enable overlayfs on a specific nix store path
      set -euo pipefail

      if [ $# -ne 1 ]; then
        echo "Usage: $0 <path>"
        exit 1
      fi

      PACKAGE_PATH="$1"
      PACKAGE_NAME=$(basename "$1"|cut -c 34-)

      # Nixos compatibility: use systemd mount unit
      #shellcheck disable=SC1091
      source /etc/os-release || true
      if [[ "$ID" == "nixos" ]]; then
        # This script is used in NixOS test only for the moment
        SYSTEMD_DIR="/run/systemd/system"
      else
        SYSTEMD_DIR="/etc/systemd/system"
      fi

      # Create required directories for overlay
      echo "$PACKAGE_NAME"
      mkdir -p "/var/lib/overlay/$PACKAGE_NAME/"{upper,work}

      PACKAGE_MOUNT_PATH=$(systemd-escape -p --suffix=mount "$PACKAGE_PATH")

      cat > "$SYSTEMD_DIR/$PACKAGE_MOUNT_PATH" <<EOF
      [Unit]
      Description=Overlay mount for PostgreSQL extension $PACKAGE_NAME

      [Mount]
      What=overlay
      Type=overlay
      Options=lowerdir=$PACKAGE_PATH,upperdir=/var/lib/overlay/$PACKAGE_NAME/upper,workdir=/var/lib/overlay/$PACKAGE_NAME/work

      [Install]
      WantedBy=multi-user.target
      EOF

      systemctl daemon-reload
      systemctl start "$PACKAGE_MOUNT_PATH"
    '';
  };
  switchPgNetVersion = writeShellApplication {
    name = "switch_pg_net_version";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      # Create version switcher script
      set -euo pipefail

      # Check if the required environment variables are set
      if [ -z "''${EXT_WRAPPER:-}" ]; then
        echo "Error: EXT_WRAPPER environment variable is not set."
        exit 1
      fi

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

      VERSION="$1"
      echo "$VERSION"

      # Enable overlay on the wrapper package to be able to switch version
      ${lib.getExe enableOverlayOnPackage} "$EXT_WRAPPER"

      # Check if version exists
      EXT_WRAPPER_LIB="$EXT_WRAPPER/lib"
      PG_NET_LIB_TO_USE="$EXT_WRAPPER_LIB/pg_net-$VERSION${postgresql.dlSuffix}"
      if [ ! -f "$PG_NET_LIB_TO_USE" ]; then
        echo "Error: Version $VERSION not found in $EXT_WRAPPER_LIB"
        echo "Available versions:"
        #shellcheck disable=SC2012
        ls "$EXT_WRAPPER_LIB"/pg_net-*${postgresql.dlSuffix} 2>/dev/null | sed 's/.*pg_net-/  /' | sed 's/${postgresql.dlSuffix}$//' || echo "  No versions found"
        exit 1
      fi

      # Update library symlink
      ln -sfnv "$PG_NET_LIB_TO_USE" "$EXT_WRAPPER_LIB/pg_net${postgresql.dlSuffix}"

      # Update control file
      EXT_WRAPPER_SHARE="$EXT_WRAPPER/share/postgresql/extension"
      echo "default_version = '$VERSION'" > "$EXT_WRAPPER_SHARE/pg_net.control"
      cat "$EXT_WRAPPER_SHARE/pg_net--$VERSION.control" >> "$EXT_WRAPPER_SHARE/pg_net.control"

      echo "Successfully switched pg_net to version $VERSION"
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
      ] ++ lib.optional (version == "0.6") libuv;

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

      env.NIX_CFLAGS_COMPILE = lib.optionalString (lib.versionOlder version "0.19.1") "-Wno-error";

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
  paths = packages;
  nativeBuildInputs = [ makeWrapper ];
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

    makeWrapper ${lib.getExe switchPgNetVersion} $out/bin/switch_pg_net_version \
      --prefix EXT_WRAPPER : "$out"
  '';

  passthru = {
    inherit versions numberOfVersions switchPgNetVersion;
    pname = "${pname}-all";
    version =
      "multi-" + lib.concatStringsSep "-" (map (v: lib.replaceStrings [ "." ] [ "-" ] v) versions);
  };
}
