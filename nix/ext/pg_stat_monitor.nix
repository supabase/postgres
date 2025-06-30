{
  lib,
  stdenv,
  fetchFromGitHub,
  postgresql,
  buildEnv,
}:
let
  pname = "pg_stat_monitor";

  # Load version configuration from external file
  allVersions = (builtins.fromJSON (builtins.readFile ./versions.json)).${pname};

  # Filter versions compatible with current PostgreSQL version
  supportedVersions = lib.filterAttrs (
    _: value: builtins.elem (lib.versions.major postgresql.version) value.postgresql
  ) allVersions;

  # Derived version information
  versions = lib.naturalSort (lib.attrNames supportedVersions);
  latestVersion = lib.last versions;
  numberOfVersions = builtins.length versions;
  packages = builtins.attrValues (
    lib.mapAttrs (name: value: build name value.hash value.revision) supportedVersions
  );

  # Build function for individual versions
  build =
    version: hash: revision:
    stdenv.mkDerivation rec {
      inherit pname version;

      buildInputs = [ postgresql ];

      src = fetchFromGitHub {
        owner = "percona";
        repo = pname;
        rev = "refs/tags/${revision}";
        inherit hash;
      };

      makeFlags = [ "USE_PGXS=1" ];

      installPhase = ''
        mkdir -p $out/{lib,share/postgresql/extension}

        # Install shared library with version suffix
        mv ${pname}${postgresql.dlSuffix} $out/lib/${pname}-${version}${postgresql.dlSuffix}

        # Create version-specific control file
        sed -e "/^default_version =/d" \
            -e "s|^module_pathname = .*|module_pathname = '\$libdir/${pname}-${version}'|" \
          ${pname}.control > $out/share/postgresql/extension/${pname}--${version}.control

        # For the latest version, create default control file and symlink and copy SQL upgrade scripts
        if [[ "${version}" == "${latestVersion}" ]]; then
          {
            echo "default_version = '${version}'"
            cat $out/share/postgresql/extension/${pname}--${version}.control
          } > $out/share/postgresql/extension/${pname}.control
          ln -sfn ${pname}-${latestVersion}${postgresql.dlSuffix} $out/lib/${pname}${postgresql.dlSuffix}
          cp *.sql $out/share/postgresql/extension
        else
          mv ./pg_stat_monitor--${version}.sql.in $out/share/postgresql/extension/pg_stat_monitor--${version}.sql
        fi
      '';

      meta = with lib; {
        description = "Query Performance Monitoring Tool for PostgreSQL";
        homepage = "https://github.com/percona/${pname}";
        license = licenses.postgresql;
        broken = lib.versionOlder postgresql.version "15";
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
    # Verify all expected library files are present
    expectedFiles=${toString (numberOfVersions + 1)}
    actualFiles=$(ls -l $out/lib/${pname}*${postgresql.dlSuffix} | wc -l)

    if [[ "$actualFiles" != "$expectedFiles" ]]; then
      echo "Error: Expected $expectedFiles library files, found $actualFiles"
      echo "Files found:"
      ls -la $out/lib/*${postgresql.dlSuffix} || true
      exit 1
    fi
  '';

  passthru = {
    inherit versions numberOfVersions;
    pname = "${pname}-all";
    version =
      "multi-" + lib.concatStringsSep "-" (map (v: lib.replaceStrings [ "." ] [ "-" ] v) versions);
  };
}
