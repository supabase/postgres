{
  lib,
  stdenv,
  fetchFromGitHub,
  postgresql,
  buildEnv,
}:
let
  pname = "pg_textsearch";

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
    lib.mapAttrs (name: value: build name value.hash) supportedVersions
  );

  # Build function for individual versions
  build =
    version: hash:
    stdenv.mkDerivation {
      inherit pname version;

      src = fetchFromGitHub {
        owner = "timescale";
        repo = "pg_textsearch";
        rev = "refs/tags/v${version}";
        inherit hash;
      };

      buildInputs = [ postgresql ];

      makeFlags = [ "USE_PGXS=1" ];

      installPhase = ''
        mkdir -p $out/{lib,share/postgresql/extension}

        # Install shared library with version suffix
        mv ${pname}${postgresql.dlSuffix} $out/lib/${pname}-${version}${postgresql.dlSuffix}

        # Create version-specific control file
        sed -e "/^default_version =/d" \
            -e "s|^module_pathname = .*|module_pathname = '\$libdir/${pname}-${version}'|" \
          ${pname}.control > $out/share/postgresql/extension/${pname}--${version}.control

        # Copy SQL file to install the specific version
        cp sql/${pname}--${version}.sql $out/share/postgresql/extension/${pname}--${version}.sql

        # For the latest version, copy sql upgrade scripts, default control file and symlink
        if [[ "${version}" == "${latestVersion}" ]]; then
          cp sql/*.sql $out/share/postgresql/extension
          {
            echo "default_version = '${version}'"
            cat $out/share/postgresql/extension/${pname}--${version}.control
          } > $out/share/postgresql/extension/${pname}.control
          ln -sfn ${pname}-${latestVersion}${postgresql.dlSuffix} $out/lib/${pname}${postgresql.dlSuffix}
        fi
      '';

      meta = with lib; {
        description = "Full-text search with BM25 ranking for PostgreSQL";
        homepage = "https://github.com/timescale/pg_textsearch";
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

  passthru = {
    inherit versions numberOfVersions pname;
    version =
      "multi-" + lib.concatStringsSep "-" (map (v: lib.replaceStrings [ "." ] [ "-" ] v) versions);
  };
}
