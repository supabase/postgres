{ lib
, stdenv
, fetchFromGitHub
, postgresql
, lz4
, openssl
, zlib
, mbedtls
, pkg-config
, autoPatchelfHook
, glibc
, gcc-unwrapped
, cmake
, ninja
, git
, readline
, flex
, bison
, libxml2
, libxslt
, libcxx
, glib
, ncurses
, patchelf
}:


let
  duckdbVersion = "17d598fc4472c64969f47f86c30fce75c4d64ed4";
  duckdbSource = fetchFromGitHub {
    owner = "duckdb";
    repo = "duckdb";
    rev = "${duckdbVersion}";
    sha256 = "sha256-/j/DaUzsfACI5Izr4lblkYmIEmKsOXr760UTwC0l/qg=";
  };

  # Build DuckDB
  ourDuckdb = stdenv.mkDerivation rec {
    pname = "duckdb";
    version = duckdbVersion;
    src = duckdbSource;
    nativeBuildInputs = [ cmake ninja ];
    buildInputs = [ openssl ];

    cmakeFlags = [
      "-DCMAKE_BUILD_TYPE=Release"
      "-DBUILD_SHARED_LIBS=ON"
    ];

    installPhase = ''
      runHook preInstall
      
      mkdir -p $out/{lib,include}
      find . -name "*.so" -type f -exec install -Dm755 {} $out/lib/ \;
      cp -r ${duckdbSource}/src/include $out/
      
      runHook postInstall
    '';

    postInstall = ''
      patchelf --print-rpath "$out/lib/libsqlite3_api_wrapper.so"
      patchelf --remove-rpath $out/lib/libsqlite3_api_wrapper.so
      patchelf --set-rpath "${lib.makeLibraryPath buildInputs}" $out/lib/libsqlite3_api_wrapper.so
      patchelf --print-rpath "$out/lib/libsqlite3_api_wrapper.so"

    '';

  };

in
stdenv.mkDerivation rec {
  pname = "pg_duckdb";
  version = "0.0.1";
  src = fetchFromGitHub {
    owner = "duckdb";
    repo = "pg_duckdb";
    rev = "main";
    sha256 = "sha256-QhU1Tme1P2ujturF8IpUM28DFhsgE83Xh7FpHiG7UVk=";
  };

  nativeBuildInputs = [ 
    pkg-config 
    autoPatchelfHook 
    git 
    flex 
    bison
    gcc-unwrapped
  ];

  buildInputs = [
    postgresql
    lz4
    openssl
    zlib
    mbedtls
    glibc
    glibc.dev
    ourDuckdb
    readline
    libxml2
    libxslt
    libcxx
    glib
    ncurses
    patchelf
  ];

  NIX_CFLAGS_COMPILE = toString ([
    "-I${postgresql}/include"
    "-I${postgresql}/include/server"
    "-I${ourDuckdb}/include"
    "-I${ourDuckdb}/include/duckdb"
    "-I${glibc.dev}/include"
    "-I${stdenv.cc.cc}/include"
    "-I${stdenv.cc.libc.dev}/include"
    "-isystem ${stdenv.cc.libc.dev}/include"
    "-Wno-error"
    "-Wno-error=deprecated-declarations"
  ]);

  prePatch = ''
    mkdir -p third_party/duckdb
    cp -r ${ourDuckdb}/include/* third_party/duckdb/
    cp -r ${ourDuckdb}/include/duckdb/* third_party/duckdb/

    mkdir -p include/pgduckdb
    cp -r ${src}/include include/pgduckdb/

    sed -i 's|FULL_DUCKDB_LIB = .*|FULL_DUCKDB_LIB = ${ourDuckdb}/lib/libduckdb.so|' Makefile
    sed -i 's|duckdb: third_party/duckdb/Makefile $(FULL_DUCKDB_LIB)|duckdb: $(FULL_DUCKDB_LIB)|' Makefile
    sed -i '/third_party\/duckdb\/Makefile:/,/git submodule update --init --recursive/d' Makefile
    sed -i '/$(FULL_DUCKDB_LIB):/,/EXTENSION_CONFIGS=/ {
      /$(FULL_DUCKDB_LIB):/!d
      /$(FULL_DUCKDB_LIB):/c\
$(FULL_DUCKDB_LIB):\
\t@echo "Using pre-built DuckDB from ${ourDuckdb}/lib/libduckdb.so"
    }' Makefile

    sed -i 's|third_party/duckdb/Makefile||g' Makefile
  '';

  buildPhase = ''
    runHook preBuild
    make USE_PGXS=1 \
      PG_CONFIG=${postgresql}/bin/pg_config \
      INCLUDEDIR=${postgresql}/include \
      INCLUDEDIR_SERVER=${postgresql}/include/server \
      PGXS=${postgresql}/lib/pgxs/src/makefiles/pgxs.mk \
      PG_LIB=${postgresql.lib}/lib \
      FULL_DUCKDB_LIB=${ourDuckdb}/lib/libduckdb.so \
      SHLIB_LINK="-Wl,-rpath,''\" \
      CPPFLAGS="-I${ourDuckdb}/include -I${ourDuckdb}/include/duckdb"
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib $out/share/postgresql/extension
    cp *.so $out/lib/
    cp *.control $out/share/postgresql/extension/
    cp sql/*.sql $out/share/postgresql/extension/
    runHook postInstall
  '';

  postFixup = ''
    echo "Before patchelf:"
    patchelf --print-rpath $out/lib/pg_duckdb.so

    patchelf --remove-rpath $out/lib/pg_duckdb.so
    patchelf --set-rpath "${lib.makeLibraryPath buildInputs}" $out/lib/pg_duckdb.so

    echo "After patchelf:"
    patchelf --print-rpath $out/lib/pg_duckdb.so

    rpath=$(patchelf --print-rpath $out/lib/pg_duckdb.so)
    echo "RPATH for pg_duckdb.so: $rpath"

    if [[ "$rpath" == *"/build/"* ]]; then
      echo "Error: RPATH still contains /build/ path"
      exit 1
    fi
  '';

  meta = with lib; {
    description = "PostgreSQL extension for querying Postgres tables using DuckDB";
    homepage = "https://github.com/duckdb/pg_duckdb";
    license = licenses.mit;
    platforms = platforms.linux;
    maintainers = with maintainers; [ ];
  };
}
