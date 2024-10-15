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
#first we need to build duckdb from source so this we create a derivation for duckdb
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
    #in the cmake flags we specify the extensions we want to build with duckdb
    # in the -DBUILD_EXTENSIONS= flag
    cmakeFlags = [
      "-DCMAKE_BUILD_TYPE=Release"
      "-DBUILD_SHARED_LIBS=ON"
      "-DCMAKE_CXX_VISIBILITY_PRESET=default"
      "-DBUILD_EXTENSIONS='parquet;icu;tpch;tpcds;fts;json;httpfs'"
    ];
    #pg 16 requires the correct suffix for the shared library 
    # so we use the postgresql.dlSuffix to get the correct suffix per system (.so for linux and .dylib for darwin)
    installPhase = ''
      runHook preInstall
      
      mkdir -p $out/{lib,include}
      find . -name "*${postgresql.dlSuffix}" -type f -exec install -Dm755 {} $out/lib/ \;
      cp -r ${duckdbSource}/src/include $out/
      
      runHook postInstall
    '';
    #we need to set the correct rpath for the shared library so that it can find the dependencies/other packages can find it
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
#this is our main derivation for pg_duckdb
stdenv.mkDerivation rec {
  pname = "pg_duckdb";
  version = "0.0.1";
  src = fetchFromGitHub {
    owner = "duckdb";
    repo = "pg_duckdb";
    rev = "7eb10c7574f5bc9c570f008e295bc9e895c55144";
    sha256 = "sha256-WlBwSbHtdrf+iSYlQ+V2aAJqwn8rBmVFf9ASbXxnJXc=";
  };
  #some deps are needed by all systems, some are only needed by linux or darwin
  #so we use lib.optionals to add them conditionally based on the system we are building on
  nativeBuildInputs = [
    pkg-config
    git
    flex
    bison
    gcc
  ] ++ lib.optionals stdenv.isLinux [ autoPatchelfHook ];
  #for the non-nix-initiated, buildInputs are the dependencies needed to build and run the package
  # nativeBuildInputs are the dependencies needed to build the package and are not included in the final package
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
    glib
    glibc
    libcxx
    gcc.cc.lib
  ] ++ lib.optionals stdenv.isDarwin [
    darwin.apple_sdk.frameworks.Security
    darwin.libobjc
    darwin.apple_sdk.frameworks.Foundation
  ];
  #as discussed here 
  # https://discourse.nixos.org/t/env-nix-cflags-compile-vs-cxxflags/39192/2?u=samrose
  # NIX_C(XX)FLAGS are guaranteed to be passed to compiler because nix’s stdenv’s wrap the compiler binaries and mangles the flags. 
  #CFLAGS and CXXFLAGS are convention used by most build systems and C/C++ projects, 
  # but there are times when they do not work [...].
  # Preferred way to pass these flags:
  # 1.Use the projects build system way
  # 2. C(XX)FLAGS   
  # 3. NIX_C(XX)FLAGS as last resort
  # in this case we use NIX_CFLAGS_COMPILE because we needed to intervene into the flags used by the project
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
    "-I${glibc.dev}/include"
    "-isystem ${stdenv.cc.cc}/include/c++/${stdenv.cc.version}"
    "-isystem ${stdenv.cc.cc}/include/c++/${stdenv.cc.version}/${stdenv.hostPlatform.config}"
    "-isystem ${stdenv.cc.cc}/include/c++/${stdenv.cc.version}/backward"
    "-isystem ${stdenv.cc.libc.dev}/include"
  ] ++ lib.optionals stdenv.isDarwin [
    "-L${postgresql}/lib"
    "-I${darwin.apple_sdk.frameworks.Security}/Headers"
    "-I${darwin.libobjc}/include"
    "-I${darwin.apple_sdk.frameworks.Foundation}/Headers"
  ]);

  NIX_CXXFLAGS_COMPILE = NIX_CFLAGS_COMPILE;
  #Here, we're doing some operations before building the package
  # that override the default behavior of the Makefile
  # We're copying the duckdb headers to the third_party/duckdb directory
  # and the pg_duckdb headers to the include/pgduckdb directory.
  # 
  # We're also setting the correct paths for the duckdb library
  # and adding the lz4 include path to the CPPFLAGS.
  #
  # We're also removing the third_party/duckdb/Makefile target from the Makefile 
  # because we're using a pre-built duckdb library in the ourDuckdb package above.
  #
  # We remove the git submodule update command from the Makefile bacause nix cannot
  # fetch submodules during the build phase, and because we already have the duckdb pacakge built
  # We set the var FULL_DUCKDB_LIB to the path of the ourDuckdb library
  # WE append the lz4 include path to the CPPFLAGS 
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
  #we set the paths for the include and library paths for the build
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
# in the buildPhase we set the flags for the build
# we set the flags for the build based on the system we are building on
# some of the flags are universal, and some are specific to darwin
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
  #we set the rpath for the shared library so that it can find the dependencies
  # we're using patchelf for linux and install_name_tool for darwin
  postFixup = lib.optionalString stdenv.isLinux ''
    patchelf --set-rpath "${lib.makeLibraryPath buildInputs}" $out/lib/pg_duckdb${postgresql.dlSuffix}
  '' + lib.optionalString stdenv.isDarwin ''
    install_name_tool -change ${ourDuckdb}/lib/libduckdb${postgresql.dlSuffix} @rpath/libduckdb${postgresql.dlSuffix} $out/lib/pg_duckdb${postgresql.dlSuffix}
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
