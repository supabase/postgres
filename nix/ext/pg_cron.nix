{
  pkgs,
  lib,
  stdenv,
  fetchFromGitHub,
  postgresql,
}:

let
  pname = "pg_cron";
  allVersions = (builtins.fromJSON (builtins.readFile ./versions.json)).${pname};
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
  };
}
