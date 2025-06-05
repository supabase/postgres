{
  pkgs,
  lib,
  stdenv,
  fetchFromGitHub,
  libkrb5,
  openssl,
  postgresql,
}:
#adapted from https://github.com/NixOS/nixpkgs/blob/master/pkgs/servers/sql/postgresql/ext/pgaudit.nix
let
  pname = "pgaudit";
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
        ''
        + lib.optionalString (version == "1.7.1") ''
          mv ${pname}--1.7--1.7.1.sql ${pname}--1.7.0--1.7.1.sql
        '';

      installPhase = ''
        mkdir -p $out/{lib,share/postgresql/extension}
        mv ${pname}${postgresql.dlSuffix} $out/lib/${pname}-${version}${postgresql.dlSuffix}

        create_sql_files() {
          cp *.sql $out/share/postgresql/extension
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
        description = "Open Source PostgreSQL Audit Logging";
        homepage = "https://github.com/pgaudit/pgaudit";
        changelog = "https://github.com/pgaudit/pgaudit/releases/tag/${source.version}";
        license = licenses.postgresql;
        inherit (postgresql.meta) platforms;
      };
    };
  allVersions = (builtins.fromJSON (builtins.readFile ./versions.json)).${pname};
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
    inherit versions numberOfVersions;
    pname = "${pname}-all";
    version =
      "multi-" + lib.concatStringsSep "-" (map (v: lib.replaceStrings [ "." ] [ "-" ] v) versions);
  };
}
