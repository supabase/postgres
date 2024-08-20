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
}:

let
  # Specify the exact version of DuckDB that pg_duckdb expects
  duckdbVersion = "17d598fc4472c64969f47f86c30fce75c4d64ed4"; # Update this to the correct version

  # Fetch the DuckDB source code
  duckdbSource = fetchFromGitHub {
    owner = "duckdb";
    repo = "duckdb";
    rev = "17d598fc4472c64969f47f86c30fce75c4d64ed4";
    sha256 = "sha256-/eTIJ95k6LxB26rpLtIHCYKzIQ41E5iZIBxx68c+D+A="; # Replace with the correct hash
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

  nativeBuildInputs = [ 
    pkg-config 
    autoPatchelfHook
    cmake
  ];

  buildInputs = [ 
    postgresql
    postgresql.lib
    lz4
    openssl
    zlib
    mbedtls
    glibc
    gcc-unwrapped.lib
  ];

  makeFlags = [ 
    "USE_PGXS=1" 
    "PG_CONFIG=${postgresql}/bin/pg_config"
  ];

  prePatch = ''
    # Create the third_party/duckdb directory and copy DuckDB source
    mkdir -p third_party/duckdb
    cp -r ${duckdbSource}/* third_party/duckdb/

    # Create an empty .depend file
    touch .depend

    # Modify the Makefile to conditionally include .depend
    sed -i 's/include .depend/-include .depend/' Makefile
  '';

  preBuild = ''
    # Ensure correct DuckDB paths are used
    sed -i 's|-Lthird_party/duckdb/build/$(DUCKDB_BUILD_TYPE)/src|-L./third_party/duckdb/build/$(DUCKDB_BUILD_TYPE)/src|g' Makefile
    sed -i 's|-Ithird_party/duckdb/src/include|-I./third_party/duckdb/src/include|g' Makefile

    # Remove DuckDB build steps from the Makefile
    sed -i '/^duckdb:/,/^clean-duckdb:/d' Makefile
    sed -i 's/all: duckdb $(OBJS) .depend/all: $(OBJS)/' Makefile
    sed -i '/install: install-duckdb/d' Makefile

    # Patch Makefile.global to use absolute paths
    sed -i 's|include $(PGXS)|include ${postgresql}/lib/pgxs/src/makefiles/pgxs.mk|' Makefile.global

    # Add system include paths
    sed -i '1iCPPFLAGS += -I${stdenv.cc.libc.dev}/include -I${glibc.dev}/include' Makefile

    # Build DuckDB
    (
      cd third_party/duckdb
      mkdir -p build
      cd build
      cmake -DCMAKE_BUILD_TYPE=Release ..
      make -j $NIX_BUILD_CORES
    )
  '';

  NIX_CFLAGS_COMPILE = "-Wno-error -isystem ${stdenv.cc.cc}/include/c++/${stdenv.cc.cc.version} -isystem ${stdenv.cc.cc}/include/c++/${stdenv.cc.cc.version}/${stdenv.hostPlatform.config}";

  dontConfigure = true;

  buildPhase = ''
    make -j $NIX_BUILD_CORES
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