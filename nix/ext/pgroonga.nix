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

    # Modify the main PGroonga SQL file to include MeCab plugin registration
    for sql_file in $out/share/postgresql/extension/pgroonga-*.sql; do
      echo "SELECT pgroonga_command('plugin_register ${supabase-groonga}/lib/groonga/plugins/tokenizers/mecab.so');" >> $sql_file
    done

    cat << EOF > $out/share/postgresql/extension/pgroonga_set_paths.sql
    DO \$\$
    BEGIN
      SET pgroonga.log_path TO current_setting('data_directory') || '/groonga.log';
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