{
  lib,
  stdenv,
  fetchFromGitHub,
  postgresql,
}:

let
  source =
    if lib.versionAtLeast postgresql.version "15" then
      {
        version = "2.1.0";
        hash = "sha256-STJVvvrLVLe1JevNu6u6EftzAWv+X+J8lu66su7Or2s=";
      }
    else
      {
        version = "1.1.1";
        hash = "sha256-S4N4Xnbkz57ue6f/eGjuRi64xT0NXjpMJiNNZnbbvbU=";
      };
in

stdenv.mkDerivation rec {
  pname = "pg_stat_monitor";
  inherit (source) version;

  buildInputs = [ postgresql ];

  src = fetchFromGitHub {
    owner = "percona";
    repo = pname;
    rev = "refs/tags/${version}";
    hash = source.hash;
  };

  makeFlags = [ "USE_PGXS=1" ];

  installPhase = ''
    mkdir -p $out/{lib,share/postgresql/extension}

    cp *${postgresql.dlSuffix}      $out/lib
    cp *.sql     $out/share/postgresql/extension
    cp *.control $out/share/postgresql/extension
  '';

  meta = with lib; {
    description = "Query Performance Monitoring Tool for PostgreSQL";
    homepage = "https://github.com/percona/${pname}";
    platforms = postgresql.meta.platforms;
    license = licenses.postgresql;
  };
}
