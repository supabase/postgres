# { lib, stdenv, fetchFromGitHub, postgresql, lz4, openssl, zlib, mbedtls
# , pkg-config, autoPatchelfHook, glibc, gcc-unwrapped, cmake, ninja, git
# , readline, flex, bison, libxml2, libxslt, libcxx, glib, ncurses }:
# let
#   duckdbVersion = "17d598fc4472c64969f47f86c30fce75c4d64ed4";
#   duckdbSource = fetchFromGitHub {
#     owner = "duckdb";
#     repo = "duckdb";
#     rev = "${duckdbVersion}";
#     sha256 = "sha256-/j/DaUzsfACI5Izr4lblkYmIEmKsOXr760UTwC0l/qg=";
#   };
#   # Build DuckDB
#   ourDuckdb = stdenv.mkDerivation rec {
#     pname = "duckdb";
#     version = duckdbVersion;
#     src = duckdbSource;
#     nativeBuildInputs = [ cmake ninja ];
#     buildInputs = [ openssl ];
#     #TODO may need BUILD_ICU=ON
#     cmakeFlags = [
#       "-DBUILD_UNITTESTS=OFF"
#       "-DBUILD_SHELL=OFF"
#       "-DBUILD_SHARED_LIBS=ON"
#       "-DBUILD_ALL_EXT=ON"
#     ];
#     installPhase = ''
#       mkdir -p $out/{lib,source}
#       find . -name "*.so" -exec cp {} $out/lib/ \;
#       cp -r ${duckdbSource}/* $out/source/
#     '';
#   };
#   findHeaderDirs = dir:
#     let
#       hasHeaderFile = files:
#         lib.any (file: lib.hasSuffix ".hpp" file || lib.hasSuffix ".h" file)
#         files;
#       getSubDirs = dir:
#         lib.attrNames (lib.filterAttrs (name: type: type == "directory")
#           (builtins.readDir dir));

#       findDirs = dir:
#         let
#           contents = builtins.readDir dir;
#           files = lib.attrNames contents;
#           subDirs = getSubDirs dir;

#           dirFlag = if hasHeaderFile files then [ dir ] else [ ];
#           subDirFlags =
#             lib.concatMap (subDir: findDirs "${dir}/${subDir}") subDirs;
#         in dirFlag ++ subDirFlags;
#     in findDirs dir;
#   # Function to recursively find "include" directories and create symlinks
#   symlinkIncludes = baseDir: destDir:
#     let
#       contents = builtins.readDir baseDir;
#       dirs = lib.filterAttrs (name: type: type == "directory") contents;

#       handleDir = name:
#         if builtins.match "include.*" name != null then
#           let
#             subContents = builtins.readDir "${baseDir}/${name}";
#             subDirs = lib.filterAttrs (subName: subType: subType == "directory")
#               subContents;
#           in lib.concatStrings (lib.mapAttrsToList (subName: _: ''
#             if [ ! -e ${destDir}/${subName} ]; then
#               mkdir -p ${destDir}/${subName}
#               ln -s ${baseDir}/${name}/${subName}/* ${destDir}/${subName}/
#             else
#               echo "Skipping ${subName}, directory already exists"
#             fi
#           '') subDirs)
#         else
#           symlinkIncludes "${baseDir}/${name}" destDir;

#       actions =
#         lib.concatStrings (lib.mapAttrsToList (name: _: handleDir name) dirs);
#     in actions;
#   generateIncludeFlags = dir: lib.concatMapStringsSep " " (d: "-I${d}") (findHeaderDirs dir);
#   duckdbIncludes = generateIncludeFlags "${ourDuckdb}/source";
#   duckdbExtensionIncludes = generateIncludeFlags "${ourDuckdb}/source/extension";
# in stdenv.mkDerivation rec {
#   pname = "pg_duckdb";
#   version = "0.0.1";
#   src = fetchFromGitHub {
#     owner = "duckdb";
#     repo = "pg_duckdb";
#     rev = "main";
#     sha256 = "sha256-wo8Bh6yaER+P12i1+pHxzPvwx1xvtOKWB2nPnQgGFzM=";
#   };
#   nativeBuildInputs = [ pkg-config autoPatchelfHook cmake ninja git flex bison ];
#   buildInputs = [
#     postgresql
#     postgresql.lib
#     lz4
#     openssl
#     zlib
#     mbedtls
#     glibc
#     gcc-unwrapped.lib
#     ourDuckdb
#     readline
#     flex
#     bison
#     libxml2
#     libxslt
#     libcxx
#     glib
#     ncurses
#   ];
#   makeFlags = [
#     "USE_PGXS=1"
#     "PG_CONFIG=${postgresql}/bin/pg_config"
#     "INCLUDEDIR=${postgresql}/include"
#     "INCLUDEDIR_SERVER=${postgresql}/include/server"
#     "PGXS=${postgresql}/lib/pgxs/src/makefiles/pgxs.mk"
#     "PG_LIB=${postgresql.lib}/lib"
#     "FULL_DUCKDB_LIB=${ourDuckdb}/lib/libduckdb.so"
#     "DUCKDB_BUILD_TYPE=release"
#   ];
#   NIX_CFLAGS_COMPILE = toString ([
#     "-I${postgresql}/include"
#     "-I${postgresql}/include/server"
#     "-isystem ${ourDuckdb}/source/extension/jemalloc/jemalloc/include"
#     "-include ${ourDuckdb}/source/extension/jemalloc/jemalloc/include/jemalloc/internal/jemalloc_preamble.h"
#     "-DJEMALLOC_NO_PRIVATE_NAMESPACE"
#     ''-DCONFIG_DEBUG="duckdb_jemalloc::config_debug"''
#     ''-Dmalloc_printf="duckdb_jemalloc::malloc_printf"''
#     ''-Djemalloc_abort="duckdb_jemalloc::jemalloc_abort"''
#     ''-Dmake_shared_ptr="std::make_shared"''
#     ''-DReplacementScanInput="duckdb::optional_ptr<duckdb::ReplacementScanData>"''
#     ''-DGetFullPath\(input\)="((input)->table_name)"''
#   ] ++ (lib.optional stdenv.cc.isGNU
#     "-include ${stdenv.cc.cc}/include/c++/${stdenv.cc.cc.version}/cstddef") ++ [
#       "-Wno-error"
#       "-Wno-error=deprecated-declarations"
#       "-isystem ${stdenv.cc.cc}/include/c++/${stdenv.cc.cc.version}"
#       "-isystem ${stdenv.cc.cc}/include/c++/${stdenv.cc.cc.version}/${stdenv.hostPlatform.config}"
#       "-I."
#       "-Iinclude"
#     ] ++ (lib.concatMap (dir: [ "-I${dir}" ])
#       (findHeaderDirs "${ourDuckdb}/source"))
#     ++ (lib.concatMap (dir: [ "-I${dir}" ])
#       (findHeaderDirs "${ourDuckdb}/source/extension"))
#     ++ (lib.concatMap (dir: [ "-I${dir}" ])
#       (findHeaderDirs "${ourDuckdb}/source/extension/jemalloc")));
  
#   CXXFLAGS = toString ([
#     "-I${postgresql}/include"
#     "-I${postgresql}/include/server"
#     "-I${ourDuckdb}/source"
#     "-I${ourDuckdb}/source/extension"
#     "-Iinclude"
#     ''-DCONFIG_DEBUG="duckdb_jemalloc::config_debug"''
#     ''-Dmalloc_printf="duckdb_jemalloc::malloc_printf"''
#     ''-Djemalloc_abort="duckdb_jemalloc::jemalloc_abort"''
#     ''-Dmake_shared_ptr="std::make_shared"''
#     ''-DReplacementScanInput="duckdb::optional_ptr<duckdb::ReplacementScanData>"''
#     ''-DGetFullPath\(input\)="((input)->table_name)"''
#   ]);

# prePatch = ''
#   # Generate include flags for DuckDB source and extensions
#   # Ensure correct DuckDB paths are used
#   echo "Copying DuckDB source..."
#   mkdir -p third_party/duckdb
#   ${symlinkIncludes "${ourDuckdb}/source" "include"}
#   cp -r ${ourDuckdb}/source/* third_party/duckdb/
  
#   # Modify Makefile
#   sed -i 's|FULL_DUCKDB_LIB = .*|FULL_DUCKDB_LIB = ${ourDuckdb}/lib/libduckdb.so|' Makefile
#   sed -i 's|duckdb: third_party/duckdb/Makefile $(FULL_DUCKDB_LIB)|duckdb: $(FULL_DUCKDB_LIB)|' Makefile
  
#   # Remove the problematic lines completely
#   sed -i '/third_party\/duckdb\/Makefile:/,/git submodule update --init --recursive/d' Makefile
  
#   # Update the FULL_DUCKDB_LIB target
#   sed -i '/$(FULL_DUCKDB_LIB):/,/EXTENSION_CONFIGS=/ {
#     /$(FULL_DUCKDB_LIB):/!d
#     /$(FULL_DUCKDB_LIB):/c\
# $(FULL_DUCKDB_LIB):\
# \t@echo "Using pre-built DuckDB from ${ourDuckdb}/lib/libduckdb.so"
#   }' Makefile
  
#   sed -i 's|include Makefile.global|# include Makefile.global|' Makefile
  
#   # Replace PG_CPPFLAGS
#   echo "Header directories included in PG_CPPFLAGS:"
#   sed -i 's|^override PG_CPPFLAGS += .*|override PG_CPPFLAGS = -Iinclude -I${ourDuckdb}/source/src/include -I${ourDuckdb}/source/third_party/re2 -std=c++17 -Wno-sign-compare -std=c++17 -Wno-sign-compare|' Makefile
  
#   # Replace SHLIB_LINK
#   sed -i 's|^SHLIB_LINK .*|SHLIB_LINK = -Wl,-rpath,${postgresql.lib}/lib/ -lpq -L${postgresql.lib}/lib -lduckdb -L${ourDuckdb}/lib -lstdc++ -llz4|' Makefile
  
#   touch .depend
#   sed -i 's/include .depend/-include .depend/' Makefile
  
#   # Debug output
#   echo "Content of PG_CPPFLAGS line in Makefile:"
#   grep "^override PG_CPPFLAGS" Makefile
# '';

#   dontConfigure = true;
#   buildPhase = ''
#     echo "Starting pg_duckdb build..."
#     make -j $NIX_BUILD_CORES VERBOSE=1 NIX_CFLAGS_COMPILE="$NIX_CFLAGS_COMPILE" CXXFLAGS="$CXXFLAGS"
#     echo "pg_duckdb build complete"
#   '';
#   installPhase = ''
#     mkdir -p $out/lib $out/share/postgresql/extension
#     cp *.so $out/lib/
#     cp *.control $out/share/postgresql/extension/
#     cp sql/*.sql $out/share/postgresql/extension/
#   '';
#   meta = with lib; {
#     description =
#       "PostgreSQL extension for querying Postgres tables using DuckDB";
#     homepage = "https://github.com/duckdb/pg_duckdb";
#     license = licenses.mit;
#     platforms = platforms.linux;
#     maintainers = with maintainers; [ ];
#   };
# }
































{ lib, stdenv, fetchFromGitHub, postgresql, lz4, openssl, zlib, mbedtls
, pkg-config, autoPatchelfHook, glibc, gcc-unwrapped, cmake, ninja, git
, readline, flex, bison, libxml2, libxslt, libcxx, glib, ncurses }:

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
      "-DBUILD_UNITTESTS=OFF"
      "-DBUILD_SHELL=OFF"
      "-DBUILD_SHARED_LIBS=ON"
      "-DBUILD_ALL_EXT=ON"
    ];
    installPhase = ''
      mkdir -p $out/{lib,include}
      find . -name "*.so" -exec cp {} $out/lib/ \;
      cp -r src/include $out/
    '';
  };

in stdenv.mkDerivation rec {
  pname = "pg_duckdb";
  version = "0.0.1";
  src = fetchFromGitHub {
    owner = "duckdb";
    repo = "pg_duckdb";
    rev = "main";
    sha256 = "sha256-wo8Bh6yaER+P12i1+pHxzPvwx1xvtOKWB2nPnQgGFzM=";
  };

  nativeBuildInputs = [ pkg-config autoPatchelfHook cmake ninja git flex bison ];
  buildInputs = [
    postgresql
    lz4
    openssl
    zlib
    mbedtls
    glibc
    gcc-unwrapped.lib
    ourDuckdb
    readline
    libxml2
    libxslt
    libcxx
    glib
    ncurses
  ];

  makeFlags = [
    "USE_PGXS=1"
    "PG_CONFIG=${postgresql}/bin/pg_config"
    "INCLUDEDIR=${postgresql}/include"
    "INCLUDEDIR_SERVER=${postgresql}/include/server"
    "PGXS=${postgresql}/lib/pgxs/src/makefiles/pgxs.mk"
    "PG_LIB=${postgresql.lib}/lib"
    "FULL_DUCKDB_LIB=${ourDuckdb}/lib/libduckdb.so"
  ];

  NIX_CFLAGS_COMPILE = toString ([
    "-I${postgresql}/include"
    "-I${postgresql}/include/server"
    "-I${ourDuckdb}/include"
    "-Wno-error"
    "-Wno-error=deprecated-declarations"
  ]);

  CXXFLAGS = toString ([
    "-I${postgresql}/include"
    "-I${postgresql}/include/server"
    "-I${ourDuckdb}/include"
    "-std=c++17"
  ]);

  prePatch = ''
    mkdir -p third_party/duckdb
    cp -r ${ourDuckdb}/include/* third_party/duckdb/
    
    sed -i 's|FULL_DUCKDB_LIB = .*|FULL_DUCKDB_LIB = ${ourDuckdb}/lib/libduckdb.so|' Makefile
    sed -i 's|duckdb: third_party/duckdb/Makefile $(FULL_DUCKDB_LIB)|duckdb: $(FULL_DUCKDB_LIB)|' Makefile
    sed -i '/third_party\/duckdb\/Makefile:/,/git submodule update --init --recursive/d' Makefile
    sed -i '/$(FULL_DUCKDB_LIB):/,/EXTENSION_CONFIGS=/ {
      /$(FULL_DUCKDB_LIB):/!d
      /$(FULL_DUCKDB_LIB):/c\
$(FULL_DUCKDB_LIB):\
\t@echo "Using pre-built DuckDB from ${ourDuckdb}/lib/libduckdb.so"
    }' Makefile
    
    sed -i 's|include Makefile.global|# include Makefile.global|' Makefile
  '';

  dontConfigure = true;

  buildPhase = ''
    make -j $NIX_BUILD_CORES $makeFlags
  '';

  installPhase = ''
    mkdir -p $out/lib $out/share/postgresql/extension
    cp *.so $out/lib/
    cp *.control $out/share/postgresql/extension/
    cp sql/*.sql $out/share/postgresql/extension/
  '';

  meta = with lib; {
    description = "PostgreSQL extension for querying Postgres tables using DuckDB";
    homepage = "https://github.com/duckdb/pg_duckdb";
    license = licenses.mit;
    platforms = platforms.linux;
    maintainers = with maintainers; [ ];
  };
}