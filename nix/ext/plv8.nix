{ stdenv
, lib
, fetchFromGitHub
, v8
, perl
, postgresql
# For passthru test on various systems, and local development on macos
# not we are not currently using passthru tests but retaining for possible contrib
# to nixpkgs 
, runCommand
, coreutils
, gnugrep
, clang
, xcbuild
, darwin
, patchelf
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "plv8";
  version = "3.1.10";

  src = fetchFromGitHub {
    owner = "plv8";
    repo = "plv8";
    rev = "v${finalAttrs.version}";
    hash = "sha256-g1A/XPC0dX2360Gzvmo9/FSQnM6Wt2K4eR0pH0p9fz4=";
  };

  patches = [
    # Allow building with system v8.
    # https://github.com/plv8/plv8/pull/505 (rejected)
    ./0001-build-Allow-using-V8-from-system.patch
  ];

  nativeBuildInputs = [
    perl
  ] ++ lib.optionals stdenv.isDarwin [
    clang
    xcbuild
  ];

  buildInputs = [
    v8
    postgresql
  ] ++ lib.optionals stdenv.isDarwin [
    darwin.apple_sdk.frameworks.CoreFoundation
    darwin.apple_sdk.frameworks.Kerberos
  ];

  buildFlags = [ "all" ];

  makeFlags = [
    # Nixpkgs build a v8 monolith instead of separate v8_libplatform.
    "USE_SYSTEM_V8=1"
    "V8_OUTDIR=${v8}/lib"
     "PG_CONFIG=${postgresql}/bin/pg_config"
  ] ++ lib.optionals stdenv.isDarwin [
    "CC=${clang}/bin/clang"
    "CXX=${clang}/bin/clang++"
    "SHLIB_LINK=-L${v8}/lib -lv8_monolith -Wl,-rpath,${v8}/lib"
  ] ++ lib.optionals (!stdenv.isDarwin) [
    "SHLIB_LINK=-lv8"
  ];

  NIX_LDFLAGS = (lib.optionals stdenv.isDarwin [
    "-L${postgresql}/lib"
    "-L${v8}/lib"
    "-lv8_monolith"
    "-lpq"
    "-lpgcommon"
    "-lpgport"
    "-F${darwin.apple_sdk.frameworks.CoreFoundation}/Library/Frameworks"
    "-framework" "CoreFoundation"
    "-F${darwin.apple_sdk.frameworks.Kerberos}/Library/Frameworks"
    "-framework" "Kerberos"
    "-undefined" "dynamic_lookup"
    "-flat_namespace"
  ]); 

  installFlags = [
    # PGXS only supports installing to postgresql prefix so we need to redirect this
    "DESTDIR=${placeholder "out"}"
  ];

  # No configure script.
  dontConfigure = true;

  postPatch = ''
    patchShebangs ./generate_upgrade.sh
    substituteInPlace generate_upgrade.sh \
      --replace " 2.3.10 " " 2.3.10 2.3.11 2.3.12 2.3.13 2.3.14 2.3.15 "

    ${lib.optionalString stdenv.isDarwin ''
      # Replace g++ with clang++ in Makefile
      sed -i 's/g++/clang++/g' Makefile
    ''}
  '';

 postInstall = ''
    # Move the redirected to proper directory.
    # There appear to be no references to the install directories
    # so changing them does not cause issues.
    mv "$out/nix/store"/*/* "$out"
    rmdir "$out/nix/store"/* "$out/nix/store" "$out/nix"

    # Handle different PostgreSQL versions
    if [ "${lib.versions.major postgresql.version}" = "15" ]; then
      mv "$out/lib/plv8-${finalAttrs.version}.so" "$out/lib/plv8.so"
      ln -s "$out/lib/plv8.so" "$out/lib/plv8-${finalAttrs.version}.so"
      sed -i 's|module_pathname = '"'"'$libdir/plv8-[0-9.]*'"'"'|module_pathname = '"'"'$libdir/plv8'"'"'|' "$out/share/postgresql/extension/plv8.control"
      sed -i 's|module_pathname = '"'"'$libdir/plv8-[0-9.]*'"'"'|module_pathname = '"'"'$libdir/plv8'"'"'|' "$out/share/postgresql/extension/plcoffee.control"
      sed -i 's|module_pathname = '"'"'$libdir/plv8-[0-9.]*'"'"'|module_pathname = '"'"'$libdir/plv8'"'"'|' "$out/share/postgresql/extension/plls.control"

      ${lib.optionalString stdenv.isDarwin ''
        install_name_tool -add_rpath "${v8}/lib" $out/lib/plv8.so
        install_name_tool -add_rpath "${postgresql}/lib" $out/lib/plv8.so
        install_name_tool -add_rpath "${stdenv.cc.cc.lib}/lib" $out/lib/plv8.so
        install_name_tool -change @rpath/libv8_monolith.dylib ${v8}/lib/libv8_monolith.dylib $out/lib/plv8.so
      ''}

      ${lib.optionalString (!stdenv.isDarwin) ''
        ${patchelf}/bin/patchelf --set-rpath "${v8}/lib:${postgresql}/lib:${stdenv.cc.cc.lib}/lib" $out/lib/plv8.so
      ''}
    else
      ${lib.optionalString stdenv.isDarwin ''
        install_name_tool -add_rpath "${v8}/lib" $out/lib/plv8-${finalAttrs.version}${postgresql.dlSuffix}
        install_name_tool -add_rpath "${postgresql}/lib" $out/lib/plv8-${finalAttrs.version}${postgresql.dlSuffix}
        install_name_tool -add_rpath "${stdenv.cc.cc.lib}/lib" $out/lib/plv8-${finalAttrs.version}${postgresql.dlSuffix}
        install_name_tool -change @rpath/libv8_monolith.dylib ${v8}/lib/libv8_monolith.dylib $out/lib/plv8-${finalAttrs.version}${postgresql.dlSuffix}
      ''}

      ${lib.optionalString (!stdenv.isDarwin) ''
        ${patchelf}/bin/patchelf --set-rpath "${v8}/lib:${postgresql}/lib:${stdenv.cc.cc.lib}/lib" $out/lib/plv8-${finalAttrs.version}${postgresql.dlSuffix}
      ''}
    fi
  '';

  meta = with lib; {
    description = "V8 Engine Javascript Procedural Language add-on for PostgreSQL";
    homepage = "https://plv8.github.io/";
    platforms = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin" ];
    license = licenses.postgresql;
  };
})
