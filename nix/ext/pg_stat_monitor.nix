{
  lib,
  stdenv,
  fetchFromGitHub,
  postgresql,
}:

stdenv.mkDerivation rec {
  pname = "pg_stat_monitor";
  version = "2.1.0";

  buildInputs = [ postgresql ];

  src = fetchFromGitHub {
    owner = "percona";
    repo = pname;
    rev = "refs/tags/${version}";
    hash = "sha256-STJVvvrLVLe1JevNu6u6EftzAWv+X+J8lu66su7Or2s=";
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
    broken = lib.versionOlder postgresql.version "15";
  };
}
