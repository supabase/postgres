{ lib, stdenv, fetchFromGitHub, postgresql }:

stdenv.mkDerivation rec {
  pname = "rum";
  version = "1.3.14";

  src = fetchFromGitHub {
    owner = "postgrespro";
    repo = "rum";
    rev = version;
    hash = "sha256-VsfpxQqRBu9bIAP+TfMRXd+B3hSjuhU2NsutocNiCt8=";
  };

  buildInputs = [ postgresql ];

  makeFlags = [ "USE_PGXS=1" ];

  installPhase = ''
    install -D -t $out/lib *${postgresql.dlSuffix}
    install -D -t $out/share/postgresql/extension *.control
    install -D -t $out/share/postgresql/extension *.sql
  '';

  meta = with lib; {
    description = "Full text search index method for PostgreSQL";
    homepage = "https://github.com/postgrespro/rum";
    license = licenses.postgresql;
    platforms = postgresql.meta.platforms;
  };
}
