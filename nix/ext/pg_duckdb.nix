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
, icu
, gcc
}:

let
  duckdbVersion = "v1.1.2";
  duckdbSource = fetchFromGitHub {
    owner = "duckdb";
    repo = "duckdb";
    rev = "${duckdbVersion}";
    sha256 = "sha256-JoGGnlu2aioO6XbeUZDe23AHSBxciLSEKBWRedPuXjI=";
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
    rev = "7eb10c7574f5bc9c570f008e295bc9e895c55144";
    sha256 = "sha256-WlBwSbHtdrf+iSYlQ+V2aAJqwn8rBmVFf9ASbXxnJXc=";
  };

  nativeBuildInputs = [
    pkg-config
    autoPatchelfHook
    git
    flex
    bison
    gcc
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
    gcc.cc.lib
    icu
  ];

  NIX_CFLAGS_COMPILE = toString ([
    "-I${postgresql}/include"
    "-I${postgresql}/include/server"
    "-I${ourDuckdb}/include"
    "-I${ourDuckdb}/include/duckdb"
    "-I${glibc.dev}/include"
    "-I${stdenv.cc.cc}/include"
    "-I${stdenv.cc.libc.dev}/include"
    "-I${lz4.dev}/include"
    "-I${icu.dev}/include"
    "-isystem ${stdenv.cc.cc}/include/c++/${stdenv.cc.version}"
    "-isystem ${stdenv.cc.cc}/include/c++/${stdenv.cc.version}/${stdenv.hostPlatform.config}"
    "-isystem ${stdenv.cc.cc}/include/c++/${stdenv.cc.version}/backward"
    "-isystem ${stdenv.cc.libc.dev}/include"
    "-Wno-error"
    "-Wno-error=deprecated-declarations"
    "-DUSE_ASSERT_CHECKING"
    "-DUSE_DEBUG"
  ]);

  NIX_CXXFLAGS_COMPILE = NIX_CFLAGS_COMPILE;

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
    sed -i 's|^CPPFLAGS =.*|& -I${lz4.dev}/include|' Makefile
  '';

  preConfigure = ''
    export CPATH="${lib.makeSearchPathOutput "dev" "include" buildInputs}:$CPATH"
    export LIBRARY_PATH="${lib.makeLibraryPath buildInputs}:$LIBRARY_PATH"
    export LD_LIBRARY_PATH="${lib.makeLibraryPath buildInputs}:$LD_LIBRARY_PATH"
    export C_INCLUDE_PATH="${glibc.dev}/include:${stdenv.cc.cc}/include:$C_INCLUDE_PATH"
    export CPLUS_INCLUDE_PATH="${glibc.dev}/include:${stdenv.cc.cc}/include:$CPLUS_INCLUDE_PATH"
  '';

  buildPhase = ''
    make USE_PGXS=1 \
      PG_CONFIG=${postgresql}/bin/pg_config \
      INCLUDEDIR=${postgresql}/include \
      INCLUDEDIR_SERVER=${postgresql}/include/server \
      PGXS=${postgresql}/lib/pgxs/src/makefiles/pgxs.mk \
      PG_LIB=${postgresql.lib}/lib \
      FULL_DUCKDB_LIB=${ourDuckdb}/lib/libduckdb.so \
      SHLIB_LINK="-Wl,-rpath,${placeholder "out"}/lib" \
      USE_OPENSSL=1 \
      USE_ICU=1 \
      USE_LIBXML=1 \
      USE_LZ4=1
  '';

  installPhase = ''
    mkdir -p $out/lib $out/share/postgresql/extension
    cp *.so $out/lib/
    cp *.control $out/share/postgresql/extension/
    cp sql/*.sql $out/share/postgresql/extension/
  '';

  postFixup = ''
    patchelf --remove-rpath $out/lib/pg_duckdb.so
    patchelf --set-rpath "${lib.makeLibraryPath buildInputs}" $out/lib/pg_duckdb.so
  '';

  meta = with lib; {
    description = "PostgreSQL extension for querying Postgres tables using DuckDB";
    homepage = "https://github.com/duckdb/pg_duckdb";
    license = licenses.mit;
    platforms = platforms.linux;
    maintainers = with maintainers; [ samrose ];
  };
}
