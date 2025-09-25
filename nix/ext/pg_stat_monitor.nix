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
    owner = "olirice";
    repo = pname;
    rev = "or/logs2";
    hash = "sha256-9vCtDseZ783pVXo/Grvi4rygVxnDZXavw9+zuHXr+0A=";
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
