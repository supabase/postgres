{
  pkgs,
  lib,
  stdenv,
  fetchFromGitHub,
  postgresql,
  libsodium,
}:
let
  pname = "pgsodium";

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

  # Build function for individual pgsodium versions
  build =
    version: hash:
    stdenv.mkDerivation rec {
      inherit pname version;

      buildInputs = [
        libsodium
        postgresql
      ];

      src = fetchFromGitHub {
        owner = "michelp";
        repo = pname;
        rev = "refs/tags/v${version}";
        inherit hash;
      };

      installPhase = ''
        runHook preInstall

        mkdir -p $out/{lib,share/postgresql/extension}

        # Install shared library with version suffix
        mv ${pname}${postgresql.dlSuffix} $out/lib/${pname}-${version}${postgresql.dlSuffix}

        # Create version-specific control file
        sed -e "/^default_version =/d" \
            -e "s|^module_pathname = .*|module_pathname = '\$libdir/${pname}'|" \
          ${pname}.control > $out/share/postgresql/extension/${pname}--${version}.control

        # For the latest version, create default control file and symlink
        if [[ "${version}" == "${latestVersion}" ]]; then
          # sql/pgsodium--3.1.5--3.1.6.sql isn't a proper upgrade sql file
          cp sql/pgsodium--3.1.4--3.1.5.sql sql/pgsodium--3.1.5--3.1.6.sql
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
        description = "Modern cryptography for PostgreSQL";
        homepage = "https://github.com/michelp/${pname}";
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

  postBuild = ''
    # Verify all expected library files are present
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
  };
}
