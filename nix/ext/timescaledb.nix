{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  postgresql,
  openssl,
  libkrb5,
  buildEnv,
  makeWrapper,
  switch-ext-version,
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

      installPhase = ''
        # Run cmake install first
        cmake --install . --prefix=$out

        # TimescaleDB has two libraries:
        # 1. timescaledb.so (loader)
        # 2. timescaledb-VERSION.so (actual extension)
        # Both need to be handled for multi-version support

        # Rename the loader to be version-specific
        if [ -f $out/lib/timescaledb${postgresql.dlSuffix} ]; then
          mv $out/lib/timescaledb${postgresql.dlSuffix} $out/lib/timescaledb-${version}${postgresql.dlSuffix}
        fi

        # The versioned library (timescaledb-VERSION.so) is already correctly named

        # Create versioned control file with default_version removed and module_pathname pointing to symlink
        if [ -f $out/share/postgresql/extension/timescaledb.control ]; then
          sed -e "/^default_version =/d" \
              -e "s|^module_pathname = .*|module_pathname = '\$libdir/timescaledb'|" \
            $out/share/postgresql/extension/timescaledb.control > $out/share/postgresql/extension/timescaledb--${version}.control
          rm $out/share/postgresql/extension/timescaledb.control
        fi
      '';

      meta = with lib; {
        description = "Scales PostgreSQL for time-series data via automatic partitioning across time and space";
        homepage = "https://www.timescale.com/";
        changelog = "https://github.com/timescale/timescaledb/blob/${version}/CHANGELOG.md";
        license = licenses.asl20;
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
buildEnv {
  name = pname;
  paths = packages;
  nativeBuildInputs = [ makeWrapper ];
  postBuild = ''
    {
      echo "default_version = '${latestVersion}'"
      cat $out/share/postgresql/extension/${pname}--${latestVersion}.control
    } > $out/share/postgresql/extension/${pname}.control

    # Create symlink for the loader
    ln -sfn ${pname}-${latestVersion}${postgresql.dlSuffix} $out/lib/${pname}${postgresql.dlSuffix}

    # The versioned library symlink (timescaledb-VERSION.so files are already in place)

    # checks - adjust count since we have both loader and versioned files
    (set -x
       test "$(ls -A $out/lib/${pname}*${postgresql.dlSuffix} | wc -l)" -gt 0
    )
    makeWrapper ${lib.getExe switch-ext-version} $out/bin/switch_timescaledb_version \
      --prefix EXT_WRAPPER : "$out" --prefix EXT_NAME : "${pname}"

  '';
  pathsToLink = [
    "/lib"
    "/share/postgresql/extension"
  ];
  passthru = {
    inherit versions numberOfVersions switch-ext-version;
    pname = "${pname}-all";
    hasBackgroundWorker = true;
    defaultSettings = {
      shared_preload_libraries = [ "timescaledb" ];
    };
    version =
      "multi-" + lib.concatStringsSep "-" (map (v: lib.replaceStrings [ "." ] [ "-" ] v) versions);
  };
}
