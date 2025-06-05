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

        # Install SQL files
        sed -i '1s/^/DROP EVENT TRIGGER IF EXISTS pgaudit_ddl_command_end; \n/' *.sql
        sed -i '1s/^/DROP EVENT TRIGGER IF EXISTS pgaudit_sql_drop; \n/' *.sql
        sed -i 's/CREATE FUNCTION/CREATE OR REPLACE FUNCTION/' *.sql
        cp *.sql $out/share/postgresql/extension

        # Create version-specific control file
        sed -e "/^default_version =/d" \
            -e "s|^module_pathname = .*|module_pathname = '\$libdir/${pname}'|" \
          ${pname}.control > $out/share/postgresql/extension/${pname}--${version}.control

        # For the latest version, create default control file and symlink
        if [[ "${version}" == "${latestVersion}" ]]; then
          {
            echo "default_version = '${latestVersion}'"
            cat $out/share/postgresql/extension/${pname}--${latestVersion}.control
          } > $out/share/postgresql/extension/${pname}.control
          ln -sfn ${pname}-${latestVersion}${postgresql.dlSuffix} $out/lib/${pname}${postgresql.dlSuffix}
        fi

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
    # checks
    (set -x
       test "$(ls -A $out/lib/${pname}*${postgresql.dlSuffix} | wc -l)" = "${
         toString (numberOfVersions + 1)
       }"
    )

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
    defaultSettings = {
      "shared_preload_libraries" = pname;
    };
  };
}
