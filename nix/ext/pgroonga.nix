# { lib, stdenv, fetchurl, pkg-config, postgresql, msgpack-c, callPackage
# , makeWrapper, mecab }:

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
#   nativeBuildInputs = [ pkg-config makeWrapper ];
#   buildInputs = [ postgresql msgpack-c supabase-groonga mecab mecab-naist-jdic ];
  
#   makeFlags = [
#     "USE_PGXS=1"
#     "HAVE_MSGPACK=1"
#     "MSGPACK_PACKAGE_NAME=msgpack-c"
#     "HAVE_MECAB=1"
#     "POSTGRES_INCLUDEDIR=${postgresql}/include"
#     "POSTGRES_LIBDIR=${postgresql.lib}/lib"
#     "PG_CONFIG=${postgresql}/bin/pg_config"
#     "MECAB_CONFIG=${mecab}/bin/mecab-config"
#     "MECAB_LIBRARIES=-L${mecab}/lib -lmecab"
#     "GROONGA_INCLUDES=-I${supabase-groonga}/include"
#     "GROONGA_LIBS=-L${supabase-groonga}/lib -lgroonga"
#     "GROONGA_PLUGIN_LIBS=-L${supabase-groonga}/lib/groonga/plugins"
#   ];
  
#   configureFlags = [
#     "--with-mecab=${mecab}"
#     "--enable-mecab"
#     "--with-mecab-config=${mecab}/bin/mecab-config"
#     "--with-mecab-dict=${mecab-naist-jdic}/lib/mecab/dic/naist-jdic"
#     "--with-groonga=${supabase-groonga}"
#     "--with-groonga-plugin-dir=${supabase-groonga}/lib/groonga/plugins"
#   ];

#   preConfigure = ''
#     export MECAB_DICDIR=${mecab-naist-jdic}/lib/mecab/dic/naist-jdic
#     export GROONGA_INCLUDE_PATH=${supabase-groonga}/include
#     export GROONGA_LIB_PATH=${supabase-groonga}/lib
#     export MECAB_INCLUDE_PATH=${mecab}/include
#     export MECAB_LIB_PATH=${mecab}/lib
#     export PKG_CONFIG_PATH="${supabase-groonga}/lib/pkgconfig:$PKG_CONFIG_PATH"
#     export GRN_PLUGINS_PATH=${supabase-groonga}/lib/groonga/plugins
    
#     # Ensure MeCab is enabled
#     sed -i 's|#define HAVE_MECAB 0|#define HAVE_MECAB 1|' src/pgroonga.h
#   '';

#   installPhase = ''
#     runHook preInstall
#     make $makeFlags install DESTDIR=$out
#     install -D pgroonga${postgresql.dlSuffix} -t $out/lib/
#     install -D pgroonga.control -t $out/share/postgresql/extension
#     install -D data/pgroonga-*.sql -t $out/share/postgresql/extension
#     install -D pgroonga_database${postgresql.dlSuffix} -t $out/lib/
#     install -D pgroonga_database.control -t $out/share/postgresql/extension
#     install -D data/pgroonga_database-*.sql -t $out/share/postgresql/extension

#     for component in pgroonga_check pgroonga_wal_applier pgroonga_crash_safer pgroonga_standby_maintainer; do
#       if [ -f "$component${postgresql.dlSuffix}" ]; then
#         install -D "$component${postgresql.dlSuffix}" -t $out/lib/
#       fi
#     done

#     # Ensure Groonga plugins are accessible
#     mkdir -p $out/lib/groonga/plugins
#     cp -r ${supabase-groonga}/lib/groonga/plugins/* $out/lib/groonga/plugins/

#     # Create a wrapper script for pgroonga
#     mkdir -p $out/bin
#     makeWrapper ${postgresql}/bin/postgres $out/bin/pgroonga-postgres \
#       --set GRN_PLUGINS_PATH ${supabase-groonga}/lib/groonga/plugins \
#       --set LD_LIBRARY_PATH ${lib.makeLibraryPath buildInputs}:${supabase-groonga}/lib:$out/lib:$out/lib/groonga/plugins

#     # Create SQL scripts to apply the necessary settings
#     cat << EOF > $out/share/postgresql/extension/pgroonga_set_paths.sql
#     DO \$\$
#     BEGIN
#       SET pgroonga.log_path TO current_setting('data_directory') || '/groonga.log';
#       SET pgroonga.libgroonga_path TO '${supabase-groonga}/lib/libgroonga${stdenv.hostPlatform.extensions.sharedLibrary}';
#       SET pgroonga.groonga_plugin_path TO '${supabase-groonga}/lib/groonga/plugins';
#     END \$\$;
# EOF
#     chmod +x $out/share/postgresql/extension/pgroonga_set_paths.sql

#     runHook postInstall
#   '';

#   postFixup = ''
#     for f in $out/lib/*.so; do
#       patchelf --set-rpath "${lib.makeLibraryPath buildInputs}:${supabase-groonga}/lib:$out/lib:$out/lib/groonga/plugins" $f
#     done
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

{ lib, stdenv, fetchurl, pkg-config, postgresql, msgpack-c, callPackage, mecab, makeWrapper }:
let
  supabase-groonga = callPackage ../supabase-groonga.nix { };
in
stdenv.mkDerivation rec {
  pname = "pgroonga";
  version = "3.0.7";
  src = fetchurl {
    url = "https://packages.groonga.org/source/${pname}/${pname}-${version}.tar.gz";
    sha256 = "sha256-iF/zh4zDDpAw5fxW1WG8i2bfPt4VYsnYArwOoE/lwgM=";
  };
  nativeBuildInputs = [ pkg-config makeWrapper ];
  buildInputs = [ postgresql msgpack-c supabase-groonga mecab ];
  
  configureFlags = [
    "--with-mecab=${mecab}"
    "--enable-mecab"
    "--with-groonga=${supabase-groonga}"
    "--with-groonga-plugin-dir=${supabase-groonga}/lib/groonga/plugins"
  ];

  makeFlags = [
    "HAVE_MSGPACK=1"
    "MSGPACK_PACKAGE_NAME=msgpack-c"
    "HAVE_MECAB=1"
  ];

  preConfigure = ''
    export GROONGA_LIBS="-L${supabase-groonga}/lib -lgroonga"
    export GROONGA_CFLAGS="-I${supabase-groonga}/include"
    export MECAB_CONFIG="${mecab}/bin/mecab-config"
  '';

  installPhase = ''
    mkdir -p $out/lib $out/share/postgresql/extension $out/bin
    install -D pgroonga${postgresql.dlSuffix} -t $out/lib/
    install -D pgroonga.control -t $out/share/postgresql/extension
    install -D data/pgroonga-*.sql -t $out/share/postgresql/extension
    install -D pgroonga_database${postgresql.dlSuffix} -t $out/lib/
    install -D pgroonga_database.control -t $out/share/postgresql/extension
    install -D data/pgroonga_database-*.sql -t $out/share/postgresql/extension

    cat << EOF > $out/share/postgresql/extension/pgroonga_set_paths.sql
    DO \$\$
    BEGIN
      SET pgroonga.log_path TO current_setting('data_directory') || '/groonga.log';
      PERFORM pgroonga_command('plugin_register ${supabase-groonga}/lib/groonga/plugins/tokenizers/mecab.so');
    END \$\$;
EOF
    chmod +x $out/share/postgresql/extension/pgroonga_set_paths.sql

    makeWrapper ${postgresql}/bin/postgres $out/bin/pgroonga-postgres \
      --set LD_LIBRARY_PATH "${lib.makeLibraryPath buildInputs}:${supabase-groonga}/lib:$out/lib"

    echo "Debug: Groonga plugins directory contents:"
    ls -l ${supabase-groonga}/lib/groonga/plugins/tokenizers/
  '';

  postFixup = ''
    for f in $out/lib/*.so; do
      patchelf --set-rpath "${lib.makeLibraryPath buildInputs}:${supabase-groonga}/lib:$out/lib:${supabase-groonga}/lib/groonga/plugins/tokenizers" $f
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