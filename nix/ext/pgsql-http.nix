{ lib, stdenv, fetchFromGitHub, curl, postgresql }:

stdenv.mkDerivation rec {
  pname = "pgsql-http";
  version = "1.6.1";

  buildInputs = [ curl postgresql ];

  src = fetchFromGitHub {
    owner = "pramsey";
    repo = pname;
    rev = "refs/tags/v${version}";
    hash = "sha256-C8eqi0q1dnshUAZjIsZFwa5FTYc7vmATF3vv2CReWPM=";
  };

  installPhase = ''
    mkdir -p $out/{lib,share/postgresql/extension}

    cp *${postgresql.dlSuffix}      $out/lib
    cp *.sql     $out/share/postgresql/extension
    cp *.control $out/share/postgresql/extension
  '';

  meta = with lib; {
    description = "HTTP client for Postgres";
    homepage = "https://github.com/pramsey/${pname}";
    platforms = postgresql.meta.platforms;
    license = licenses.postgresql;
  };
}
