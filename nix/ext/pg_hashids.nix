{
  lib,
  stdenv,
  fetchFromGitHub,
  postgresql,
  buildEnv,
}:
let
  pname = "pg_hashids";
  build =
    version: hash: revision:
    stdenv.mkDerivation rec {
      inherit pname version;

      buildInputs = [ postgresql ];

      src = fetchFromGitHub {
        owner = "iCyberon";
        repo = pname;
        rev = revision;
        inherit hash;
      };

      installPhase = ''
        mkdir -p $out/{lib,share/postgresql/extension}

        mv ${pname}${postgresql.dlSuffix} $out/lib/${pname}-${version}${postgresql.dlSuffix}

        create_sql_files() {
          if test -f ${pname}--${version}.sql; then
            cp ${pname}--${version}.sql $out/share/postgresql/extension
          fi
          echo "Creating SQL files for previous versions..."
          if [[ "${version}" == "${latestVersion}" ]]; then
            cp *.sql $out/share/postgresql/extension

            # anything after 1.2.1 is unreleased
            cp pg_hashids--1.3.sql $out/share/postgresql/extension/pg_hashids--${version}.sql
            cp pg_hashids--1.2.1--1.3.sql $out/share/postgresql/extension/pg_hashids--1.2.1--${version}.sql
          fi
        }

        create_control_files() {
          sed -e "/^default_version =/d" \
              -e "s|^module_pathname = .*|module_pathname = '\$libdir/${pname}'|" \
            ${pname}.control > $out/share/postgresql/extension/${pname}--${version}.control

          if [[ "${version}" == "${latestVersion}" ]]; then
            {
              echo "default_version = '${latestVersion}'"
              cat $out/share/postgresql/extension/${pname}--${latestVersion}.control
            } > $out/share/postgresql/extension/${pname}.control
            ln -sfn ${pname}-${latestVersion}${postgresql.dlSuffix} $out/lib/${pname}${postgresql.dlSuffix}
          fi
        }

        create_sql_files
        create_control_files
      '';

      meta = with lib; {
        description = "Generate short unique IDs in PostgreSQL";
        homepage = "https://github.com/iCyberon/pg_hashids";
        license = licenses.postgresql;
        inherit (postgresql.meta) platforms;
      };
    };
  allVersions = (builtins.fromJSON (builtins.readFile ./versions.json)).pg_hashids;
  supportedVersions = lib.filterAttrs (
    _: value: builtins.elem (lib.versions.major postgresql.version) value.postgresql
  ) allVersions;
  versions = lib.naturalSort (lib.attrNames supportedVersions);
  latestVersion = lib.last versions;
  numberOfVersions = builtins.length versions;
  packages = builtins.attrValues (
    lib.mapAttrs (name: value: build name value.hash (value.revision or name)) supportedVersions
  );
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
  '';

  passthru = {
    inherit versions numberOfVersions pname;
    version =
      "multi-" + lib.concatStringsSep "-" (map (v: lib.replaceStrings [ "." ] [ "-" ] v) versions);
  };
}
