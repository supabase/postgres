{
  stdenv,
  lib,
  fetchFromGitHub,
  v8,
  perl,
  postgresql,
  # For passthru test on various systems, and local development on macos
  # not we are not currently using passthru tests but retaining for possible contrib
  # to nixpkgs
  clang,
  xcbuild,
  darwin,
  patchelf,
  buildEnv,
  nodejs_20
}:

let
  pname = "plv8";

  # Load version configuration from external file
  allVersions = (builtins.fromJSON (builtins.readFile ../versions.json)).${pname};

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
    stdenv.mkDerivation (finalAttrs: {
      inherit pname version;
      #version = "3.1.10";

      src = fetchFromGitHub {
        owner = "plv8";
        repo = "plv8";
        rev = "v${finalAttrs.version}";
        inherit hash;
      };

      patches = [
        # Allow building with system v8.
        # https://github.com/plv8/plv8/pull/505 (rejected)
        ./0001-build-Allow-using-V8-from-system-${version}.patch
      ] ++ lib.optionals (builtins.compareVersions "3.1.10" version >= 0) [
        # Apply https://github.com/plv8/plv8/pull/552/ patch to fix extension upgrade problems
        ./0001-fix-upgrade-related-woes-with-GUC-redefinitions-${version}.patch
      ];

      nativeBuildInputs =
        [
          perl
        ]
        ++ lib.optionals stdenv.isDarwin [
          clang
          xcbuild
        ];

      buildInputs =
        [
          (if (builtins.compareVersions "3.1.10" version >= 0) then v8 else nodejs_20.libv8)
          postgresql
        ]
        ++ lib.optionals stdenv.isDarwin [
          darwin.apple_sdk.frameworks.CoreFoundation
          darwin.apple_sdk.frameworks.Kerberos
        ];

      buildFlags = [ "all" ];

      makeFlags =
        [
          # Nixpkgs build a v8 monolith instead of separate v8_libplatform.
          "USE_SYSTEM_V8=1"
          "V8_OUTDIR=${v8}/lib"
          "PG_CONFIG=${postgresql}/bin/pg_config"
        ]
        ++ lib.optionals stdenv.isDarwin [
          "CC=${clang}/bin/clang"
          "CXX=${clang}/bin/clang++"
          "SHLIB_LINK=-L${v8}/lib -lv8_monolith -Wl,-rpath,${v8}/lib"
        ]
        ++ lib.optionals (!stdenv.isDarwin) [
          "SHLIB_LINK=-lv8"
        ];

      NIX_LDFLAGS = lib.optionals stdenv.isDarwin [
        "-L${postgresql}/lib"
        "-L${v8}/lib"
        "-lv8_monolith"
        "-lpq"
        "-lpgcommon"
        "-lpgport"
        "-F${darwin.apple_sdk.frameworks.CoreFoundation}/Library/Frameworks"
        "-framework"
        "CoreFoundation"
        "-F${darwin.apple_sdk.frameworks.Kerberos}/Library/Frameworks"
        "-framework"
        "Kerberos"
        "-undefined"
        "dynamic_lookup"
        "-flat_namespace"
      ];

      # No configure script.
      dontConfigure = true;

      postPatch = ''
        patchShebangs ./generate_upgrade.sh
        substituteInPlace generate_upgrade.sh \
          --replace " 3.1.8 " " 3.1.8 3.1.10 "

        ${lib.optionalString stdenv.isDarwin ''
          # Replace g++ with clang++ in Makefile
          sed -i 's/g++/clang++/g' Makefile
        ''}
      '';

      installPhase = ''
        runHook preInstall
        set -eo pipefail

        mkdir -p $out/{lib,share/postgresql/extension}

        # Install versioned library
        LIB_NAME="${pname}-${finalAttrs.version}${postgresql.dlSuffix}"
        install -Dm755 $LIB_NAME $out/lib

        if [ "${lib.versions.major postgresql.version}" = "15" ]; then
          ${lib.optionalString stdenv.isDarwin ''
            install_name_tool -add_rpath "${v8}/lib" $out/lib/$LIB_NAME
            install_name_tool -add_rpath "${postgresql}/lib" $out/lib/$LIB_NAME
            install_name_tool -add_rpath "${stdenv.cc.cc.lib}/lib" $out/lib/$LIB_NAME
            install_name_tool -change @rpath/libv8_monolith.dylib ${v8}/lib/libv8_monolith.dylib $out/lib/$LIB_NAME
          ''}

          ${lib.optionalString (!stdenv.isDarwin) ''
            ${patchelf}/bin/patchelf --set-rpath "${v8}/lib:${postgresql}/lib:${stdenv.cc.cc.lib}/lib" $out/lib/$LIB_NAME
          ''}
        else
          ${lib.optionalString stdenv.isDarwin ''
            install_name_tool -add_rpath "${v8}/lib" $out/lib/$LIB_NAME
            install_name_tool -add_rpath "${postgresql}/lib" $out/lib/$LIB_NAME
            install_name_tool -add_rpath "${stdenv.cc.cc.lib}/lib" $out/lib/$LIB_NAME
            install_name_tool -change @rpath/libv8_monolith.dylib ${v8}/lib/libv8_monolith.dylib $out/lib/$LIB_NAME
          ''}

          ${lib.optionalString (!stdenv.isDarwin) ''
            ${patchelf}/bin/patchelf --set-rpath "${v8}/lib:${postgresql}/lib:${stdenv.cc.cc.lib}/lib" $out/lib/$LIB_NAME
          ''}
        fi

        # plv8 3.2.x removed support for coffeejs and livescript
        EXTENSIONS=(${if (builtins.compareVersions "3.1.10" version >= 0) then "plv8 plcoffee plls" else "plv8"})
        for ext in "''${EXTENSIONS[@]}" ; do
          cp $ext--${version}.sql $out/share/postgresql/extension
          install -Dm644 $ext.control $out/share/postgresql/extension/$ext--${version}.control
          # Create versioned control file with modified module path
          sed -e "/^default_version =/d" \
              -e "s|^module_pathname = .*|module_pathname = '\$libdir/${pname}-${version}'|" \
            $ext.control > $out/share/postgresql/extension/$ext--${version}.control
        done

        # For the latest 3.1.x version, also create the default control file
        # for coffeejs and livescript extensions
        if [[ ${version} == "3.1.10" ]]; then
          for ext in "''${EXTENSIONS[@]}" ; do
            if [[ "$ext" != "plv8" ]]; then
              {
                echo "default_version = '${version}'"
                cat $out/share/postgresql/extension/$ext--${version}.control
              } > $out/share/postgresql/extension/$ext.control
            fi
          done
        fi

        # For the latest version, create default control file and symlink
        if [[ "${version}" == "${latestVersion}" ]]; then
          {
            echo "default_version = '${version}'"
            cat $out/share/postgresql/extension/${pname}--${version}.control
          } > $out/share/postgresql/extension/${pname}.control
          ln -sfn ${pname}-${latestVersion}${postgresql.dlSuffix} $out/lib/${pname}${postgresql.dlSuffix}
        fi

        # copy upgrade scripts
        cp upgrade/*.sql $out/share/postgresql/extension

        runHook postInstall
      '';

      meta = with lib; {
        description = "V8 Engine Javascript Procedural Language add-on for PostgreSQL";
        homepage = "https://plv8.github.io/";
        platforms = [
          "x86_64-linux"
          "aarch64-linux"
          "aarch64-darwin"
          "x86_64-darwin"
        ];
        license = licenses.postgresql;
      };
    });
in
buildEnv {
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
