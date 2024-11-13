{ lib, stdenv, fetchFromGitHub, postgresql, perl, cmake, boost }:

stdenv.mkDerivation rec {
  pname = "pgrouting";
  version = "3.4.1";

  nativeBuildInputs = [ cmake perl ];
  buildInputs = [ postgresql boost ];

  src = fetchFromGitHub {
    owner  = "pgRouting";
    repo   = pname;
    rev    = "v${version}";
    hash = "sha256-QC77AnPGpPQGEWi6JtJdiNsB2su5+aV2pKg5ImR2B0k=";
  };

  #disable compile time warnings for incompatible pointer types only on macos and pg16
  NIX_CFLAGS_COMPILE = lib.optionalString (stdenv.isDarwin && lib.versionAtLeast postgresql.version "16") 
  "-Wno-error=int-conversion -Wno-error=incompatible-pointer-types";

  cmakeFlags = [
    "-DPOSTGRESQL_VERSION=${postgresql.version}"
  ] ++ lib.optionals (stdenv.isDarwin && lib.versionAtLeast postgresql.version "16")  [
    "-DCMAKE_MACOSX_RPATH=ON"
    "-DCMAKE_SHARED_MODULE_SUFFIX=.dylib"
    "-DCMAKE_SHARED_LIBRARY_SUFFIX=.dylib"
  ];

  preConfigure = lib.optionalString (stdenv.isDarwin && lib.versionAtLeast postgresql.version "16") ''
    export DLSUFFIX=.dylib
    export CMAKE_SHARED_LIBRARY_SUFFIX=.dylib
    export CMAKE_SHARED_MODULE_SUFFIX=.dylib
    export MACOSX_RPATH=ON
  '';

  postBuild = lib.optionalString (stdenv.isDarwin && lib.versionAtLeast postgresql.version "16") ''
    shopt -s nullglob
    for file in lib/libpgrouting-*.so; do
      if [ -f "$file" ]; then
        mv "$file" "''${file%.so}.dylib"
      fi
    done
    shopt -u nullglob
  '';

  installPhase = ''
    install -D lib/*${postgresql.dlSuffix}                       -t $out/lib
    install -D sql/pgrouting--*.sql   -t $out/share/postgresql/extension
    install -D sql/common/pgrouting.control    -t $out/share/postgresql/extension
  '';

  meta = with lib; {
    description = "A PostgreSQL/PostGIS extension that provides geospatial routing functionality";
    homepage    = "https://pgrouting.org/";
    changelog   = "https://github.com/pgRouting/pgrouting/releases/tag/v${version}";
    maintainers = with maintainers; [ steve-chavez samrose ];
    platforms   = postgresql.meta.platforms;
    license     = licenses.gpl2Plus;
  };
}
