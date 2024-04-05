{ lib, stdenv, fetchFromGitHub, curl, postgresql }:

stdenv.mkDerivation rec {
  pname = "pgsql-http";
  version = "1.5.0";

  buildInputs = [ curl postgresql ];

  src = fetchFromGitHub {
    owner = "pramsey";
    repo = pname;
    rev = "refs/tags/v${version}";
    hash = "sha256-+N/CXm4arRgvhglanfvO0FNOBUWV5RL8mn/9FpNvcjY=";
  };

  installPhase = ''
    mkdir -p $out/{lib,share/postgresql/extension}

    cp *.so      $out/lib
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
