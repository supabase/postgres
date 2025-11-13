{
  pkgs,
  lib,
  stdenv,
  fetchFromGitHub,
  postgresql,
}:
let
  pname = "vector";

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
    stdenv.mkDerivation rec {
      inherit pname version;

      buildInputs = [ postgresql ];

      src = fetchFromGitHub {
        owner = "pgvector";
        repo = "pgvector";
        rev = "refs/tags/v${version}";
        inherit hash;
      };

      installPhase = ''
        mkdir -p $out/{lib,share/postgresql/extension}

        # Install shared library with version suffix
        mv ${pname}${postgresql.dlSuffix} $out/lib/${pname}-${version}${postgresql.dlSuffix}

        # Create version-specific control file
        sed -e "/^default_version =/d" \
            -e "s|^module_pathname = .*|module_pathname = '\$libdir/${pname}'|" \
          ${pname}.control > $out/share/postgresql/extension/${pname}--${version}.control

        # Copy SQL file to install the specific version
        cp sql/${pname}.sql $out/share/postgresql/extension/${pname}--${version}.sql

        # For the latest version, copy sql upgrade script, default control file and symlink
        if [[ "${version}" == "${latestVersion}" ]]; then
          cp sql/*.sql $out/share/postgresql/extension
          {
            echo "default_version = '${latestVersion}'"
            cat $out/share/postgresql/extension/${pname}--${latestVersion}.control
          } > $out/share/postgresql/extension/${pname}.control
          ln -sfn ${pname}-${latestVersion}${postgresql.dlSuffix} $out/lib/${pname}${postgresql.dlSuffix}
        fi

        runHook postInstall
      '';

      meta = with lib; {
        description = "Open-source vector similarity search for Postgres";
        homepage = "https://github.com/${src.owner}/${src.repo}";
        maintainers = with maintainers; [ olirice ];
        platforms = postgresql.meta.platforms;
        license = licenses.postgresql;
      };
    };
in
pkgs.buildEnv {
  name = pname;
  paths = packages;
  pathsToLink = [
    "/lib"
    "/share/postgresql/extension"
  ];

  passthru = {
    inherit versions numberOfVersions;
    pname = "${pname}-all";
    version =
      "multi-" + lib.concatStringsSep "-" (map (v: lib.replaceStrings [ "." ] [ "-" ] v) versions);
    pgRegressTestName = "pgvector";
  };
}
