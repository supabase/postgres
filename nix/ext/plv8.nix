{ stdenv
, lib
, fetchFromGitHub
, v8
, perl
, postgresql
, clang
, xcbuild
, darwin
, patchelf
}:

let
  source = {
    "17" = {
      version = "3.2.2";
      hash = "sha256-azO33v22EF+/sTNmwswxyDR0PhrvWfTENuLu6JgSGJ0=";
      patch = ./0001-build-Allow-using-V8-from-system-17.patch;
    };
    "15" = {
      version = "3.1.10";
      hash = "sha256-g1A/XPC0dX2360Gzvmo9/FSQnM6Wt2K4eR0pH0p9fz4=";
      patch = ./0001-build-Allow-using-V8-from-system-15.patch;
    };
  }.${lib.versions.major postgresql.version} or (throw "Source for pgaudit is not available for ${postgresql.version}");
in
stdenv.mkDerivation rec {
  pname = "plv8";
  version = source.version;

  src = fetchFromGitHub {
    owner = "plv8";
    repo = "plv8";
    rev = source.version;
    hash = source.hash;
  };

  patches = [
    # Allow building with system v8.
    # https://github.com/plv8/plv8/pull/505 (rejected)
    source.patch
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

    ${lib.optionalString stdenv.isDarwin ''
      install_name_tool -add_rpath "${v8}/lib" $out/lib/plv8-${source.version}.so
      install_name_tool -add_rpath "${postgresql}/lib" $out/lib/plv8-${source.version}.so
      install_name_tool -add_rpath "${stdenv.cc.cc.lib}/lib" $out/lib/plv8-${source.version}.so
      install_name_tool -change @rpath/libv8_monolith.dylib ${v8}/lib/libv8_monolith.dylib $out/lib/plv8-${source.version}.so
    ''}

    ${lib.optionalString (!stdenv.isDarwin) ''
      ${patchelf}/bin/patchelf --set-rpath "${v8}/lib:${postgresql}/lib:${stdenv.cc.cc.lib}/lib" $out/lib/plv8-${source.version}.so
    ''}
  '';


  meta = with lib; {
    description = "V8 Engine Javascript Procedural Language add-on for PostgreSQL";
    homepage = "https://plv8.github.io/";
    maintainers = with maintainers; [ samrose ];
    platforms = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
    license = licenses.postgresql;
  };
}