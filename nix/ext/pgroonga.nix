{ lib, stdenv, fetchurl, pkg-config, postgresql, msgpack-c, callPackage, mecab, makeWrapper, xxHash  }:
let
  supabase-groonga = callPackage ../supabase-groonga.nix { };
in
stdenv.mkDerivation rec {
  pname = "pgroonga";
  version = "3.2.5";
  src = fetchurl {
    url = "https://packages.groonga.org/source/${pname}/${pname}-${version}.tar.gz";
    sha256 = "sha256-GM9EOQty72hdE4Ecq8jpDudhZLiH3pP9ODLxs8DXcSY=";
  };
  nativeBuildInputs = [ pkg-config makeWrapper ];
  
  buildInputs = [ postgresql msgpack-c supabase-groonga mecab ] ++ lib.optionals stdenv.isDarwin [
    xxHash
  ];

  propagatedBuildInputs = [ supabase-groonga ];
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

  NIX_CFLAGS_COMPILE = lib.optionalString stdenv.isDarwin (builtins.concatStringsSep " " [
    "-Wno-error=incompatible-function-pointer-types"
    "-Wno-error=format"
    "-Wno-format"
    "-I${supabase-groonga}/include/groonga"
    "-I${xxHash}/include"
    "-DPGRN_VERSION=\"${version}\""
  ]);

  preConfigure = ''
    export GROONGA_LIBS="-L${supabase-groonga}/lib -lgroonga"
    export GROONGA_CFLAGS="-I${supabase-groonga}/include"
    export MECAB_CONFIG="${mecab}/bin/mecab-config"
    ${lib.optionalString stdenv.isDarwin ''
      export CPPFLAGS="-I${supabase-groonga}/include/groonga -I${xxHash}/include -DPGRN_VERSION=\"${version}\""
      export CFLAGS="-I${supabase-groonga}/include/groonga -I${xxHash}/include -DPGRN_VERSION=\"${version}\""
      export PG_CPPFLAGS="-Wno-error=incompatible-function-pointer-types -Wno-error=format"
    ''}
  '';

  installPhase = ''
    mkdir -p $out/lib $out/share/postgresql/extension $out/bin
    install -D pgroonga${postgresql.dlSuffix} -t $out/lib/
    install -D pgroonga.control -t $out/share/postgresql/extension
    install -D data/pgroonga-*.sql -t $out/share/postgresql/extension
    install -D pgroonga_database${postgresql.dlSuffix} -t $out/lib/
    install -D pgroonga_database.control -t $out/share/postgresql/extension
    install -D data/pgroonga_database-*.sql -t $out/share/postgresql/extension

    echo "Debug: Groonga plugins directory contents:"
    ls -l ${supabase-groonga}/lib/groonga/plugins/tokenizers/
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