{
  lib,
  stdenv,
  writeShellApplication,
  jq,
}:

let
  root = ../..;

  # Bundle all files that affect Docker image builds
  # When any of these change, the derivation hash changes
  dockerSources = stdenv.mkDerivation {
    name = "docker-image-sources";
    src = lib.fileset.toSource {
      inherit root;
      fileset = lib.fileset.unions [
        # Dockerfiles
        (root + "/Dockerfile-15")
        (root + "/Dockerfile-17")
        (root + "/Dockerfile-orioledb-17")

        # PostgreSQL configuration files (copied into images)
        (root + "/ansible/files/postgresql_config")
        (root + "/ansible/files/pgbouncer_config")
        (root + "/ansible/files/stat_extension.sql")
        (root + "/ansible/files/pgsodium_getkey_urandom.sh.j2")
        (root + "/ansible/files/postgresql_extension_custom_scripts")
        (root + "/ansible/files/walg_helper_scripts")

        # Database migrations (copied into images)
        (root + "/migrations/db")

        # Nix flake (defines the psql packages used in images)
        (root + "/flake.nix")
        (root + "/flake.lock")

        # Nix package definitions that affect slim images
        (root + "/nix/packages")
        (root + "/nix/config.nix")
        (root + "/nix/overlays")

        # PostgreSQL and extension definitions
        (root + "/nix/ext")
        (root + "/nix/postgresql")
      ];
    };

    phases = [
      "unpackPhase"
      "installPhase"
    ];
    installPhase = ''
      mkdir -p $out
      cp -r . $out/
    '';
  };
in
writeShellApplication {
  name = "docker-image-inputs-hash";

  runtimeInputs = [ jq ];

  text = ''
    set -euo pipefail

    DOCKER_SOURCES="${dockerSources}"
    INPUT_HASH=$(basename "$DOCKER_SOURCES" | cut -d- -f1)

    case "''${1:-hash}" in
      hash)
        echo "$INPUT_HASH"
        ;;
      path)
        echo "$DOCKER_SOURCES"
        ;;
      json)
        jq -n \
          --arg hash "$INPUT_HASH" \
          --arg path "$DOCKER_SOURCES" \
          '{hash: $hash, path: $path}'
        ;;
      *)
        echo "Usage: docker-image-inputs-hash [hash|path|json]" >&2
        exit 1
        ;;
    esac
  '';

  meta = {
    description = "Get the content hash of all Docker image inputs";
    longDescription = ''
      This package bundles all source files that affect Docker image builds.
      The hash is computed from the Nix store path, which changes when any
      input file changes. Use this to detect when Docker images need to be
      rebuilt and tested.

      Usage:
        docker-image-inputs-hash hash  # Get just the hash
        docker-image-inputs-hash path  # Get the Nix store path
        docker-image-inputs-hash json  # Get both as JSON
    '';
  };
}
