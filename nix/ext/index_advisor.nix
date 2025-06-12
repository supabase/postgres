{
  pkgs,
  lib,
  stdenv,
  fetchFromGitHub,
  postgresql,
}:

let
  pname = "index_advisor";
  allVersions = (builtins.fromJSON (builtins.readFile ./versions.json)).${pname};
  supportedVersions = lib.filterAttrs (
    _: value: builtins.elem (lib.versions.major postgresql.version) value.postgresql
  ) allVersions;
  versions = lib.naturalSort (lib.attrNames supportedVersions);
  latestVersion = lib.last versions;
  numberOfVersions = builtins.length versions;
  build =
    version: hash:
    stdenv.mkDerivation rec {
      inherit pname version;

      buildInputs = [ postgresql ];

      src = fetchFromGitHub {
        owner = "olirice";
        repo = pname;
        rev = "v${version}";
        inherit hash;
      };

      installPhase = ''
        mkdir -p $out/{lib,share/postgresql/extension}

        create_sql_files() {
          echo "Creating SQL files for previous versions..."
          if [[ "${version}" == "${latestVersion}" ]]; then
            cp *.sql $out/share/postgresql/extension
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
          fi
        }

        create_sql_files
        create_control_files
      '';

      meta = with lib; {
        description = "Recommend indexes to improve query performance in PostgreSQL";
        homepage = "https://github.com/olirice/index_advisor";
        license = licenses.postgresql;
        inherit (postgresql.meta) platforms;
      };
    };
  packages = builtins.attrValues (
    lib.mapAttrs (name: value: build name value.hash) supportedVersions
  );
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
