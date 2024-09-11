{ stdenv
, lib
, fetchFromGitHub
, v8
, perl
, postgresql
  # For test
, runCommand
, coreutils
, gnugrep
, clang
, patchelf
, xcbuild
, darwin
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "plv8";
  version = "3.1.5";

  src = fetchFromGitHub {
    owner = "plv8";
    repo = "plv8";
    rev = "v${finalAttrs.version}";
    hash = "sha256-LodC2eQJSm5fLckrjm2RuejZhmOyQMJTv9b0iPCnzKQ=";
  };

  patches = [
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
    "USE_SYSTEM_V8=1"
    "V8_OUTDIR=${v8}/lib"
    "PG_CONFIG=${postgresql}/bin/pg_config"
  ] ++ lib.optionals stdenv.isDarwin [
    "CC=${clang}/bin/clang"
    "CXX=${clang}/bin/clang++"
    "SHLIB_LINK=-L${v8}/lib -lv8_monolith -Wl,-rpath,${v8}/lib"
  ] ++ lib.optionals (!stdenv.isDarwin) [
    "SHLIB_LINK=-L${v8}/lib -lv8_monolith -Wl,-rpath,${v8}/lib"
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
  ]) ++ (lib.optionals (!stdenv.isDarwin) [
    "-L${postgresql}/lib"
    "-L${v8}/lib"
    "-lv8_monolith"
    "-lpq"
    "-lpgcommon"
    "-lpgport"
  ]);

  NIX_CFLAGS_COMPILE = [
    "-I${v8}/include"
    "-I${postgresql}/include"
    "-I${postgresql}/include/server"
    "-I${postgresql}/include/internal"
  ];

  installFlags = [
    "DESTDIR=${placeholder "out"}"
  ];

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

  preBuild = lib.optionalString stdenv.isDarwin ''
    export CC=${clang}/bin/clang
    export CXX=${clang}/bin/clang++
  '';

  postInstall = ''
    mv "$out/nix/store"/*/* "$out"
    rmdir "$out/nix/store"/* "$out/nix/store" "$out/nix"

    ${lib.optionalString stdenv.isDarwin ''
      install_name_tool -add_rpath "${v8}/lib" $out/lib/plv8-${finalAttrs.version}.so
      install_name_tool -add_rpath "${postgresql}/lib" $out/lib/plv8-${finalAttrs.version}.so
      install_name_tool -add_rpath "${stdenv.cc.cc.lib}/lib" $out/lib/plv8-${finalAttrs.version}.so
      install_name_tool -change @rpath/libv8_monolith.dylib ${v8}/lib/libv8_monolith.dylib $out/lib/plv8-${finalAttrs.version}.so
    ''}

    ${lib.optionalString (!stdenv.isDarwin) ''
      ${patchelf}/bin/patchelf --set-rpath "${v8}/lib:${postgresql}/lib:${stdenv.cc.cc.lib}/lib" $out/lib/plv8-${finalAttrs.version}.so
    ''}
  '';

  passthru = {
    tests =
      let
        postgresqlWithSelf = postgresql.withPackages (_: [
          finalAttrs.finalPackage
        ]);
      in
      {
        smoke = runCommand "plv8-smoke-test" { } ''
          export PATH=${lib.makeBinPath [
            postgresqlWithSelf
            coreutils
            gnugrep
          ]}
          db="$PWD/testdb"
          initdb "$db"
          postgres -k "$db" -D "$db" &
          pid="$!"

          for i in $(seq 1 100); do
            if psql -h "$db" -d postgres -c "" 2>/dev/null; then
              break
            elif ! kill -0 "$pid"; then
              exit 1
            else
              sleep 0.1
            fi
          done

          psql -h "$db" -d postgres -c 'CREATE EXTENSION plv8; DO $$ plv8.elog(NOTICE, plv8.version); $$ LANGUAGE plv8;' 2> "$out"
          grep -q "${finalAttrs.version}" "$out"
          kill -0 "$pid"
        '';

        regression = stdenv.mkDerivation {
          name = "plv8-regression";
          inherit (finalAttrs) src patches nativeBuildInputs buildInputs dontConfigure;

          buildPhase = ''
            runHook preBuild

            # The regression tests need to be run in the order specified in the Makefile.
            echo -e "include Makefile\nprint_regress_files:\n\t@echo \$(REGRESS)" > Makefile.regress
            REGRESS_TESTS=$(make -f Makefile.regress print_regress_files)

            ${postgresql}/lib/pgxs/src/test/regress/pg_regress \
              --bindir='${postgresqlWithSelf}/bin' \
              --temp-instance=regress-instance \
              --dbname=contrib_regression \
              $REGRESS_TESTS

            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall

            touch "$out"

            runHook postInstall
          '';
        };
      };
  };

  meta = with lib; {
    description = "V8 Engine Javascript Procedural Language add-on for PostgreSQL";
    homepage = "https://plv8.github.io/";
    maintainers = with maintainers; [ samrose ];
    platforms = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
    license = licenses.postgresql;
    #broken = postgresql.jitSupport;
  };
})
