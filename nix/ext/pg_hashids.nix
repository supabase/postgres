{ lib, stdenv, fetchFromGitHub, postgresql }:

stdenv.mkDerivation rec {
  pname = "pg_hashids";
  version = "cd0e1b31d52b394a0df64079406a14a4f7387cd6";

  buildInputs = [ postgresql ];

  src = fetchFromGitHub {
    owner = "iCyberon";
    repo = pname;
    rev = "${version}";
    hash = "sha256-Nmb7XLqQflYZfqj0yrewfb1Hl5YgEB5wfjBunPwIuOU=";
  };

  installPhase = ''
    mkdir -p $out/{lib,share/postgresql/extension}

    cp *${postgresql.dlSuffix}      $out/lib
    cp *.sql     $out/share/postgresql/extension
    cp *.control $out/share/postgresql/extension
  '';

  meta = with lib; {
    description = "Generate short unique IDs in PostgreSQL";
    homepage = "https://github.com/iCyberon/pg_hashids";
    maintainers = with maintainers; [ samrose ];
    platforms = postgresql.meta.platforms;
    license = licenses.postgresql;
  };
}
