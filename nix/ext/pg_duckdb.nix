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
, darwin
}:

let
  duckdbVersion = "v1.1.2";
  duckdbSource = fetchFromGitHub {
    owner = "duckdb";
    repo = "duckdb";
    rev = "${duckdbVersion}";
    sha256 = "sha256-JoGGnlu2aioO6XbeUZDe23AHSBxciLSEKBWRedPuXjI=";
  };


  ourDuckdb = stdenv.mkDerivation rec {
    pname = "duckdb";
    version = duckdbVersion;
    src = duckdbSource;
    nativeBuildInputs = [ cmake ninja ];
    buildInputs = [ openssl ];

    cmakeFlags = [
      "-DCMAKE_BUILD_TYPE=Release"
      "-DBUILD_SHARED_LIBS=ON"
      "-DCMAKE_CXX_VISIBILITY_PRESET=default"
      "-DBUILD_EXTENSIONS='parquet;icu;tpch;tpcds;fts;json;httpfs'"
    ];

    installPhase = ''
      runHook preInstall
      
      mkdir -p $out/{lib,include}
      find . -name "*${postgresql.dlSuffix}" -type f -exec install -Dm755 {} $out/lib/ \;
      cp -r ${duckdbSource}/src/include $out/
      
      runHook postInstall
    '';

    postInstall = lib.optionalString stdenv.isLinux ''
      patchelf --print-rpath "$out/lib/libsqlite3_api_wrapper${postgresql.dlSuffix}"
      patchelf --remove-rpath $out/lib/libsqlite3_api_wrapper${postgresql.dlSuffix}
      patchelf --set-rpath "${lib.makeLibraryPath buildInputs}" $out/lib/libsqlite3_api_wrapper${postgresql.dlSuffix}
      patchelf --print-rpath "$out/lib/libsqlite3_api_wrapper${postgresql.dlSuffix}"
    ''+ lib.optionalString stdenv.isDarwin ''
      install_name_tool -id $out/lib/libduckdb${postgresql.dlSuffix} $out/lib/libduckdb${postgresql.dlSuffix}
      install_name_tool -change @rpath/libduckdb${postgresql.dlSuffix} $out/lib/libduckdb${postgresql.dlSuffix} $out/lib/libsqlite3_api_wrapper${postgresql.dlSuffix}
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
    git
    flex
    bison
    gcc
  ] ++ lib.optionals stdenv.isLinux [ autoPatchelfHook ];

  buildInputs = [
    postgresql
    lz4
    openssl
    zlib
    mbedtls
    ourDuckdb
    readline
    libxml2
    libxslt
    ncurses
    icu
  ] ++ lib.optionals stdenv.isLinux [
    patchelf
  ] ++ lib.optionals stdenv.isDarwin [
    darwin.apple_sdk.frameworks.Security
    darwin.libobjc
    darwin.apple_sdk.frameworks.Foundation
  ];

  NIX_CFLAGS_COMPILE = toString ([
    "-I${postgresql}/include"
    "-I${postgresql}/include/server"
    "-I${ourDuckdb}/include"
    "-I${ourDuckdb}/include/duckdb"
    "-I${lz4.dev}/include"
    "-I${icu.dev}/include"
    "-Wno-error"
    "-Wno-error=deprecated-declarations"
    "-DUSE_ASSERT_CHECKING"
    "-DUSE_DEBUG"
  ] ++ lib.optionals stdenv.isLinux [
    "-I${stdenv.cc.cc}/include"
    "-I${stdenv.cc.libc.dev}/include"
  ] ++ lib.optionals stdenv.isDarwin [
    "-L${postgresql}/lib"
    "-I${darwin.apple_sdk.frameworks.Security}/Headers"
    "-I${darwin.libobjc}/include"
    "-I${darwin.apple_sdk.frameworks.Foundation}/Headers"
  ]);

  NIX_CXXFLAGS_COMPILE = NIX_CFLAGS_COMPILE;

  prePatch = ''
    mkdir -p third_party/duckdb
    cp -r ${ourDuckdb}/include/* third_party/duckdb/
    cp -r ${ourDuckdb}/include/duckdb/* third_party/duckdb/

    mkdir -p include/pgduckdb
    cp -r ${src}/include include/pgduckdb/

    sed -i 's|FULL_DUCKDB_LIB = .*|FULL_DUCKDB_LIB = ${ourDuckdb}/lib/libduckdb.${postgresql.dlSuffix}|' Makefile
    sed -i 's|duckdb: third_party/duckdb/Makefile $(FULL_DUCKDB_LIB)|duckdb: $(FULL_DUCKDB_LIB)|' Makefile
    sed -i '/third_party\/duckdb\/Makefile:/,/git submodule update --init --recursive/d' Makefile
    sed -i '
    /^duckdb:/,/^[^ \t]/ {
      /^duckdb:/b
      /^[^ \t]/b
      d
    }
    /^duckdb:/ {
      c\
    duckdb: $(FULL_DUCKDB_LIB)\
    $(FULL_DUCKDB_LIB):\
      @echo "Using pre-built DuckDB from ${ourDuckdb}/lib/libduckdb.${if stdenv.isDarwin then "dylib" else "so"}"
    }
    ' Makefile
    sed -i 's|third_party/duckdb/Makefile||g' Makefile
    sed -i 's|^CPPFLAGS =.*|& -I${lz4.dev}/include|' Makefile
  '';

  preConfigure = ''
    export CPATH="${lib.makeSearchPathOutput "dev" "include" buildInputs}:$CPATH"
    export LIBRARY_PATH="${lib.makeLibraryPath buildInputs}:$LIBRARY_PATH"
    export LD_LIBRARY_PATH="${lib.makeLibraryPath buildInputs}:$LD_LIBRARY_PATH"
  '' + lib.optionalString stdenv.isLinux ''
    export C_INCLUDE_PATH="${stdenv.cc.cc}/include:${stdenv.cc.libc.dev}/include:$C_INCLUDE_PATH"
    export CPLUS_INCLUDE_PATH="${stdenv.cc.cc}/include:${stdenv.cc.libc.dev}/include:$CPLUS_INCLUDE_PATH"
  '' + lib.optionalString stdenv.isDarwin ''
    export CPLUS_INCLUDE_PATH="${darwin.apple_sdk.frameworks.Security}/Headers:${darwin.libobjc}/include:${darwin.apple_sdk.frameworks.Foundation}/Headers:$CPLUS_INCLUDE_PATH"
  '';

buildPhase = let
  darwinFlags = lib.optionalString stdenv.isDarwin ''
    SHLIB_LINK+=" -framework Security -framework Foundation \
                  -Wl,-undefined,dynamic_lookup \
                  -Wl,-dead_strip_dylibs" \
    CFLAGS+=" -I${darwin.apple_sdk.frameworks.Security}/Headers \
              -I${darwin.apple_sdk.frameworks.Foundation}/Headers \
              -I${postgresql}/include -I${postgresql}/include/server" \
    LDFLAGS+=" -L${darwin.libobjc}/lib -L${postgresql.lib}/lib -L${postgresql}/lib" \
    LIBS+=" -lobjc -lpostgres"
  '';
in ''
  make USE_PGXS=1 \
    PG_CONFIG=${postgresql}/bin/pg_config \
    INCLUDEDIR=${postgresql}/include \
    INCLUDEDIR_SERVER=${postgresql}/include/server \
    PGXS=${postgresql}/lib/pgxs/src/makefiles/pgxs.mk \
    PG_LIB=${postgresql.lib}/lib \
    FULL_DUCKDB_LIB=${ourDuckdb}/lib/libduckdb${postgresql.dlSuffix} \
    SHLIB_LINK="-Wl,-rpath,${ourDuckdb}/lib \
                -L${ourDuckdb}/lib -lduckdb" \
    USE_OPENSSL=1 \
    USE_ICU=1 \
    USE_LIBXML=1 \
    USE_LZ4=1 \
    ${darwinFlags}
'';

  installPhase = ''
    mkdir -p $out/lib $out/share/postgresql/extension
    cp *${postgresql.dlSuffix} $out/lib/
    cp *.control $out/share/postgresql/extension/
    cp sql/*.sql $out/share/postgresql/extension/
  '';

  postFixup = lib.optionalString stdenv.isLinux ''
    patchelf --set-rpath "${lib.makeLibraryPath buildInputs}" $out/lib/pg_duckdb${postgresql.dlSuffix}
  '' + lib.optionalString stdenv.isDarwin ''
    install_name_tool -change ${ourDuckdb}/lib/libduckdb${postgresql.dlSuffix} @rpath/libduckdb${postgresql.dlSuffix} $out/lib/pg_duckdb${postgresql.dlSuffix}
    #install_name_tool -add_rpath ${ourDuckdb}/lib $out/lib/pg_duckdb${postgresql.dlSuffix}
    install_name_tool -add_rpath ${postgresql.lib}/lib $out/lib/pg_duckdb${postgresql.dlSuffix}
  '';

  meta = with lib; {
    description = "PostgreSQL extension for querying Postgres tables using DuckDB";
    homepage = "https://github.com/duckdb/pg_duckdb";
    license = licenses.mit;
    platforms = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
    maintainers = with maintainers; [ samrose ];
  };
}