{ lib, stdenv, fetchFromGitHub, postgresql }:

stdenv.mkDerivation rec {
  pname = "index_advisor";
  version = "0.2.0";

  buildInputs = [ postgresql ];

  src = fetchFromGitHub {
    owner = "olirice";
    repo = pname;
    rev = "v${version}";
    hash = "sha256-G0eQk2bY5CNPMeokN/nb05g03CuiplRf902YXFVQFbs=";
  };

  installPhase = ''
    mkdir -p $out/{lib,share/postgresql/extension}

    cp *.sql     $out/share/postgresql/extension
    cp *.control $out/share/postgresql/extension
  '';

  meta = with lib; {
    description = "Recommend indexes to improve query performance in PostgreSQL";
    homepage = "https://github.com/olirice/index_advisor";
    maintainers = with maintainers; [ samrose ];
    platforms = postgresql.meta.platforms;
    license = licenses.postgresql;
  };
}
