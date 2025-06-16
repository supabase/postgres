{
  pkgs,
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  postgresql,
  openssl,
  libkrb5,
}:

let
  pname = "timescaledb";
  build =
    version: hash: _revision:
    stdenv.mkDerivation rec {
      inherit pname version;

      nativeBuildInputs = [ cmake ];
      buildInputs = [
        postgresql
        openssl
        libkrb5
      ];

      src = fetchFromGitHub {
        owner = "timescale";
        repo = "timescaledb";
        rev = version;
        inherit hash;
      };

      cmakeFlags = [
        "-DSEND_TELEMETRY_DEFAULT=OFF"
        "-DREGRESS_CHECKS=OFF"
        "-DTAP_CHECKS=OFF"
        "-DAPACHE_ONLY=1"
      ] ++ lib.optionals stdenv.isDarwin [ "-DLINTER=OFF" ];

      postPatch = ''
        for x in CMakeLists.txt sql/CMakeLists.txt; do
          if [ -f "$x" ]; then
            substituteInPlace "$x" \
              --replace 'DESTINATION "''${PG_SHAREDIR}/extension"' "DESTINATION \"$out/share/postgresql/extension\""
          fi
        done

        for x in src/CMakeLists.txt src/loader/CMakeLists.txt tsl/src/CMakeLists.txt; do
          if [ -f "$x" ]; then
            substituteInPlace "$x" \
              --replace 'DESTINATION ''${PG_PKGLIBDIR}' "DESTINATION \"$out/lib\""
          fi
        done
      '';

      postInstall = ''
        if [ -f $out/lib/timescaledb.so ]; then
          mv $out/lib/timescaledb.so $out/lib/timescaledb-${version}.so
        fi
        if [ -f $out/share/postgresql/extension/timescaledb.control ]; then
          mv $out/share/postgresql/extension/timescaledb.control $out/share/postgresql/extension/timescaledb--${version}.control
        fi
      '';

      meta = with lib; {
        description = "Scales PostgreSQL for time-series data via automatic partitioning across time and space";
        homepage = "https://www.timescale.com/";
        changelog = "https://github.com/timescale/timescaledb/blob/${version}/CHANGELOG.md";
        license = licenses.postgresql;
        inherit (postgresql.meta) platforms;
      };
    };

  allVersions = (builtins.fromJSON (builtins.readFile ./versions.json)).timescaledb;
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
pkgs.buildEnv {
  name = pname;
  paths = packages;
  postBuild = ''
    {
      echo "default_version = '${latestVersion}'"
      cat $out/share/postgresql/extension/${pname}--${latestVersion}.control
    } > $out/share/postgresql/extension/${pname}.control
    ln -sfn ${pname}-${latestVersion}${postgresql.dlSuffix} $out/lib/${pname}${postgresql.dlSuffix}

    # checks
    (set -x
       test "$(ls -A $out/lib/${pname}*${postgresql.dlSuffix} | wc -l)" = "${
         toString (numberOfVersions + 1)
       }"
    )
  '';
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
