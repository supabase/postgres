{ lib, stdenv, fetchFromGitHub, curl, postgresql }:

stdenv.mkDerivation rec {
  pname = "pgsql-http";
  version = "1.6.0";

  buildInputs = [ curl postgresql ];

  src = fetchFromGitHub {
    owner = "pramsey";
    repo = pname;
    rev = "refs/tags/v${version}";
    hash = "sha256-CPHfx7vhWfxkXsoKTzyFuTt47BPMvzi/pi1leGcuD60=";
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
    maintainers = with maintainers; [ samrose ];
    platforms = postgresql.meta.platforms;
    license = licenses.postgresql;
  };
}
