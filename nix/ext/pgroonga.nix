# { lib, stdenv, fetchurl, pkg-config, postgresql, msgpack-c, mecab, callPackage
# , patchelf }:
# let
#   supabase-groonga = callPackage ../supabase-groonga.nix { };
#   mecab-naist-jdic = callPackage ./mecab-naist-jdic { };
# in stdenv.mkDerivation rec {
#   pname = "pgroonga";
#   version = "3.0.7";
#   src = fetchurl {
#     url =
#       "https://packages.groonga.org/source/${pname}/${pname}-${version}.tar.gz";
#     sha256 = "sha256-iF/zh4zDDpAw5fxW1WG8i2bfPt4VYsnYArwOoE/lwgM=";
#   };
#   nativeBuildInputs = [ pkg-config patchelf ];
#   buildInputs =
#     [ postgresql msgpack-c supabase-groonga mecab mecab-naist-jdic ];

#   configureFlags = [
#     "--with-mecab=${mecab}"
#     "--enable-mecab"
#     "--enable-groonga-tokenizer-mecab"
#     "--with-mecab-dict=${mecab-naist-jdic}/lib/mecab/dic/naist-jdic"
#     "--with-groonga=${supabase-groonga}"
#     "--with-groonga-token-mecab-dir=${supabase-groonga}/lib/groonga/plugins/tokenizers"
#     "--with-groonga-tokenizer-mecab=${supabase-groonga}/lib/groonga/plugins/tokenizers/mecab.so"
#     "--with-groonga-plugin-dir=${supabase-groonga}/lib/groonga/plugins"
#     "--with-pgconfigdir=${postgresql}/bin"
#     "--with-mecab-config=${mecab}/bin/mecab-config"
#   ];

#   makeFlags =
#     [ "HAVE_MSGPACK=1" "MSGPACK_PACKAGE_NAME=msgpack-c" "HAVE_MECAB=1" ];

#   buildPhase = ''
#     runHook preBuild
#     make
#     echo "Checking for MeCab-related files:"
#     find . -name "*mecab*"
#     runHook postBuild
#   '';

#   installPhase = ''
#     runHook preInstall

#     install -D pgroonga${postgresql.dlSuffix} -t $out/lib/
#     install -D pgroonga.control -t $out/share/postgresql/extension/
#     install -D data/pgroonga-*.sql -t $out/share/postgresql/extension/
#     install -D pgroonga_database${postgresql.dlSuffix} -t $out/lib/
#     install -D pgroonga_database.control -t $out/share/postgresql/extension/
#     install -D data/pgroonga_database-*.sql -t $out/share/postgresql/extension/

#     # Ensure MeCab tokenizer is available
#     if [ -f ${supabase-groonga}/lib/groonga/plugins/tokenizers/mecab.so ]; then
#       mkdir -p $out/lib/postgresql/plugins/
#       cp ${supabase-groonga}/lib/groonga/plugins/tokenizers/mecab.so $out/lib/postgresql/plugins/
#     else
#       echo "MeCab tokenizer plugin not found in Groonga installation"
#       exit 1
#     fi

#     runHook postInstall
#   '';

#   postInstall = ''
#     echo "Checking installed files:"
#     find $out -type f

#     echo "Checking for MeCab-related files in the output:"
#     find $out -name "*mecab*"
#   '';

#   postFixup = ''
#     patchelf --set-rpath "${
#       lib.makeLibraryPath [
#         mecab
#         mecab-naist-jdic
#         supabase-groonga
#         postgresql
#         stdenv.cc.cc.lib
#         msgpack-c
#       ]
#     }" $out/lib/pgroonga${postgresql.dlSuffix}
#     patchelf --set-rpath "${
#       lib.makeLibraryPath [
#         mecab
#         mecab-naist-jdic
#         supabase-groonga
#         postgresql
#         stdenv.cc.cc.lib
#         msgpack-c
#       ]
#     }" $out/lib/pgroonga_database${postgresql.dlSuffix}
#   '';

#   meta = with lib; {
#     description = "A PostgreSQL extension to use Groonga as the index";
#     longDescription = ''
#       PGroonga is a PostgreSQL extension to use Groonga as the index.
#       PostgreSQL supports full text search against languages that use only alphabet and digit.
#       It means that PostgreSQL doesn't support full text search against Japanese, Chinese and so on.
#       You can use super fast full text search feature against all languages by installing PGroonga into your PostgreSQL.
#     '';
#     homepage = "https://pgroonga.github.io/";
#     changelog = "https://github.com/pgroonga/pgroonga/releases/tag/${version}";
#     license = licenses.postgresql;
#     platforms = postgresql.meta.platforms;
#     maintainers = with maintainers; [ samrose ];
#   };
# }

# { lib, stdenv, fetchurl, pkg-config, postgresql, cmake, msgpack-c, mecab, callPackage }:
# let
#   supabase-groonga = callPackage ../supabase-groonga.nix { };
#   mecab-naist-jdic = callPackage ./mecab-naist-jdic { };
# in
# stdenv.mkDerivation rec {
#   pname = "pgroonga";
#   version = "3.0.7";

#   src = fetchurl {
#     url = "https://packages.groonga.org/source/${pname}/${pname}-${version}.tar.gz";
#     sha256 = "sha256-iF/zh4zDDpAw5fxW1WG8i2bfPt4VYsnYArwOoE/lwgM=";
#   };

#   nativeBuildInputs = [ cmake pkg-config ];
#   buildInputs = [ postgresql msgpack-c supabase-groonga mecab mecab-naist-jdic ];

#   makeFlags = [
#     "HAVE_MSGPACK=1"
#     "MSGPACK_PACKAGE_NAME=msgpack-c"
#   ];

#   installPhase = ''
#     install -D pgroonga${postgresql.dlSuffix} -t $out/lib/
#     install -D pgroonga.control -t $out/share/postgresql/extension
#     install -D data/pgroonga-*.sql -t $out/share/postgresql/extension

#     install -D pgroonga_database${postgresql.dlSuffix} -t $out/lib/
#     install -D pgroonga_database.control -t $out/share/postgresql/extension
#     install -D data/pgroonga_database-*.sql -t $out/share/postgresql/extension
#   '';

#   meta = with lib; {
#     description = "A PostgreSQL extension to use Groonga as the index";
#     longDescription = ''
#       PGroonga is a PostgreSQL extension to use Groonga as the index.
#       PostgreSQL supports full text search against languages that use only alphabet and digit.
#       It means that PostgreSQL doesn't support full text search against Japanese, Chinese and so on.
#       You can use super fast full text search feature against all languages by installing PGroonga into your PostgreSQL.
#     '';
#     homepage = "https://pgroonga.github.io/";
#     changelog = "https://github.com/pgroonga/pgroonga/releases/tag/${version}";
#     license = licenses.postgresql;
#     platforms = postgresql.meta.platforms;
#     maintainers = with maintainers; [ samrose ];
#   };
# }

# { lib, stdenv, fetchurl, pkg-config, postgresql, msgpack-c, callPackage, cmake, mecab }:
# let
#   supabase-groonga = callPackage ../supabase-groonga.nix { };
#   mecab-naist-jdic = callPackage ./mecab-naist-jdic { };
# in
# stdenv.mkDerivation rec {
#   pname = "pgroonga";
#   version = "3.0.7";
#   src = fetchurl {
#     url = "https://packages.groonga.org/source/${pname}/${pname}-${version}.tar.gz";
#     sha256 = "sha256-iF/zh4zDDpAw5fxW1WG8i2bfPt4VYsnYArwOoE/lwgM=";
#   };
#   patches = [ ./use-system-groonga.patch ];
#   nativeBuildInputs = [ pkg-config cmake ];
#   buildInputs = [ postgresql msgpack-c supabase-groonga mecab mecab-naist-jdic ];
#   cmakeFlags = [
#     "-DCMAKE_PREFIX_PATH=${supabase-groonga}"
#     "-DMECAB_CONFIG=${mecab}/bin/mecab-config"
#     "-DMECAB_DICT_INDEX=${mecab}/libexec/mecab/mecab-dict-index"
#     "-DMECAB_DIC_DIR=${mecab-naist-jdic}/lib/mecab/dic/naist-jdic"
#     "-DCMAKE_BUILD_TYPE=Release"
#     "-DBUILD_TESTING=OFF"
#   ];
#   preConfigure = ''
#     export CFLAGS="-I${supabase-groonga}/include -I${postgresql}/include/server -I${supabase-groonga}/include/groonga"
#     export CPPFLAGS="$CFLAGS"
#     export LDFLAGS="-L${supabase-groonga}/lib -L${postgresql}/lib"

#     # Remove the problematic /EHsc flag
#     export CFLAGS="$(echo $CFLAGS | sed 's/-EHsc//g')"
#     export CXXFLAGS="$(echo $CXXFLAGS | sed 's/-EHsc//g')"

#     # Ensure CMake doesn't add it back
#     substituteInPlace CMakeLists.txt --replace "-EHsc" ""
#   '';

#   installPhase = ''
#     install -D pgroonga${postgresql.dlSuffix} -t $out/lib/
#     install -D pgroonga.control -t $out/share/postgresql/extension
#     install -D data/pgroonga-*.sql -t $out/share/postgresql/extension
#     install -D pgroonga_database${postgresql.dlSuffix} -t $out/lib/
#     install -D pgroonga_database.control -t $out/share/postgresql/extension
#     install -D data/pgroonga_database-*.sql -t $out/share/postgresql/extension
#   '';
#   meta = with lib; {
#     description = "A PostgreSQL extension to use Groonga as the index";
#     longDescription = ''
#       PGroonga is a PostgreSQL extension to use Groonga as the index.
#       PostgreSQL supports full text search against languages that use only alphabet and digit.
#       It means that PostgreSQL doesn't support full text search against Japanese, Chinese and so on.
#       You can use super fast full text search feature against all languages by installing PGroonga into your PostgreSQL.
#     '';
#     homepage = "https://pgroonga.github.io/";
#     changelog = "https://github.com/pgroonga/pgroonga/releases/tag/${version}";
#     license = licenses.postgresql;
#     platforms = postgresql.meta.platforms;
#     maintainers = with maintainers; [ samrose ];
#   };
# }

{ lib, stdenv, fetchurl, pkg-config, postgresql, msgpack-c, callPackage
, makeWrapper, mecab }:

let
  supabase-groonga = callPackage ../supabase-groonga.nix { };
  mecab-naist-jdic = callPackage ./mecab-naist-jdic { };
in stdenv.mkDerivation rec {
  pname = "pgroonga";
  version = "3.0.7";
  src = fetchurl {
    url =
      "https://packages.groonga.org/source/${pname}/${pname}-${version}.tar.gz";
    sha256 = "sha256-iF/zh4zDDpAw5fxW1WG8i2bfPt4VYsnYArwOoE/lwgM=";
  };
  nativeBuildInputs = [ pkg-config makeWrapper ];
  buildInputs = [ postgresql msgpack-c supabase-groonga mecab mecab-naist-jdic ];
  makeFlags = [
    "USE_PGXS=1"
    "HAVE_MSGPACK=1"
    "MSGPACK_PACKAGE_NAME=msgpack-c"
    "HAVE_MECAB=1"
    "POSTGRES_INCLUDEDIR=${postgresql}/include"
    "POSTGRES_LIBDIR=${postgresql.lib}/lib"
    "PG_CONFIG=${postgresql}/bin/pg_config"
    "MECAB_CONFIG=${mecab}/bin/mecab-config"
  ];
  
  preConfigure = ''
    export MECAB_DICDIR=${mecab-naist-jdic}/lib/mecab/dic/naist-jdic
    export GROONGA_INCLUDE_PATH=${supabase-groonga}/include
    export GROONGA_LIB_PATH=${supabase-groonga}/lib
    export MECAB_INCLUDE_PATH=${mecab}/include
    export MECAB_LIB_PATH=${mecab}/lib
  '';

  buildPhase = ''
    runHook preBuild
    make $makeFlags
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    make $makeFlags install DESTDIR=$out
    install -D pgroonga${postgresql.dlSuffix} -t $out/lib/
    install -D pgroonga.control -t $out/share/postgresql/extension
    install -D data/pgroonga-*.sql -t $out/share/postgresql/extension
    install -D pgroonga_database${postgresql.dlSuffix} -t $out/lib/
    install -D pgroonga_database.control -t $out/share/postgresql/extension
    install -D data/pgroonga_database-*.sql -t $out/share/postgresql/extension
    
    for component in pgroonga_check pgroonga_wal_applier pgroonga_crash_safer pgroonga_standby_maintainer; do
      if [ -f "$component${postgresql.dlSuffix}" ]; then
        install -D "$component${postgresql.dlSuffix}" -t $out/lib/
      fi
    done
    runHook postInstall
  '';

  postFixup = ''
    for f in $out/lib/*.so; do
      patchelf --set-rpath "${lib.makeLibraryPath buildInputs}:$out/lib" $f
    done
  '';

  meta = with lib; {
    description = "A PostgreSQL extension to use Groonga as the index";
    longDescription = ''
      PGroonga is a PostgreSQL extension to use Groonga as the index.
      PostgreSQL supports full text search against languages that use only alphabet and digit.
      It means that PostgreSQL doesn't support full text search against Japanese, Chinese and so on.
      You can use super fast full text search feature against all languages by installing PGroonga into your PostgreSQL.
    '';
    homepage = "https://pgroonga.github.io/";
    changelog = "https://github.com/pgroonga/pgroonga/releases/tag/${version}";
    license = licenses.postgresql;
    platforms = postgresql.meta.platforms;
    maintainers = with maintainers; [ samrose ];
  };
}