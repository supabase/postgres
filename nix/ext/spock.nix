{
  pkgs,
  lib,
  stdenv,
  fetchFromGitHub,
  postgresql,
  makeWrapper,
  openssl,
  libkrb5,
  pam,
  zlib,
}:

let
  pname = "spock";
  build =
    version: hash:
    stdenv.mkDerivation rec {
      inherit pname version;

      src = fetchFromGitHub {
        owner = "pgEdge";
        repo = "spock";
        rev = "v${version}";
        inherit hash;
      };

      buildInputs = [ postgresql openssl libkrb5 pam zlib ];

      makeFlags = [ "USE_PGXS=1" ];

      installPhase = ''
        runHook preInstall

        mkdir -p $out/{lib,share/postgresql/extension}

        # Install versioned library
        install -Dm755 ${pname}${postgresql.dlSuffix} $out/lib/${pname}-${version}${postgresql.dlSuffix}

        # Install SQL files
        if [[ -d sql ]]; then
          cp sql/*.sql $out/share/postgresql/extension/ || true
        fi
        if [[ -f ${pname}--${version}.sql ]]; then
          cp ${pname}--${version}.sql $out/share/postgresql/extension/
        fi
        if [[ -f ${pname}.sql ]]; then
          cp ${pname}.sql $out/share/postgresql/extension/${pname}--${version}.sql
        fi

        # Install control file (modified to point to versioned library)
        sed -e "/^default_version =/d" \
            -e "s|^module_pathname = .*|module_pathname = '\$libdir/${pname}'|" \
          ${pname}.control > $out/share/postgresql/extension/${pname}--${version}.control

        runHook postInstall
      '';

      meta = with lib; {
        description = "Multi-master bi-directional replication extension for PostgreSQL";
        homepage = "https://github.com/pgEdge/spock";
        license = licenses.postgresql;
        platforms = postgresql.meta.platforms;
      };
    };

  allVersions = (builtins.fromJSON (builtins.readFile ./versions.json)).spock;
  supportedVersions = lib.filterAttrs (
    _: value: builtins.elem (lib.versions.major postgresql.version) value.postgresql
  ) allVersions;
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
  pathsToLink = [
    "/lib"
    "/share/postgresql/extension"
  ];
  postBuild = ''
    ln -sfn ${pname}-${latestVersion}${postgresql.dlSuffix} $out/lib/${pname}${postgresql.dlSuffix}

    {
      echo "default_version = '${latestVersion}'"
      cat $out/share/postgresql/extension/${pname}--${latestVersion}.control
    } > $out/share/postgresql/extension/${pname}.control

    # Create empty upgrade files between consecutive versions if needed
    previous_version=""
    for ver in ${lib.concatStringsSep " " versions}; do
      if [[ -n "$previous_version" ]]; then
        if [[ ! -f "$out/share/postgresql/extension/${pname}--''${previous_version}--''${ver}.sql" ]]; then
          touch $out/share/postgresql/extension/${pname}--''${previous_version}--''${ver}.sql
        fi
      fi
      previous_version=$ver
    done

    # Verify library files are present
    expectedFiles=${toString (numberOfVersions + 1)}
    actualFiles=$(ls -A $out/lib/${pname}*${postgresql.dlSuffix} 2>/dev/null | wc -l)

    if [[ "$actualFiles" != "$expectedFiles" ]]; then
      echo "Warning: Expected $expectedFiles library files, found $actualFiles"
      ls -la $out/lib/${pname}*${postgresql.dlSuffix} || true
    fi
  '';

  passthru = {
    inherit versions numberOfVersions pname;
    version =
      "multi-" + lib.concatStringsSep "-" (map (v: lib.replaceStrings [ "." ] [ "-" ] v) versions);
    hasBackgroundWorker = true;
    defaultSettings = {
      wal_level = "logical";
      shared_preload_libraries = [ "spock" ];
      track_commit_timestamp = "on";
    };
  };
}
