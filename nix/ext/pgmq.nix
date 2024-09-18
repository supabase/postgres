{ lib, stdenv, fetchFromGitHub, postgresql }:

stdenv.mkDerivation rec {
  pname = "pgmq";
  version = "1.4.4";
  buildInputs = [ postgresql ];
  src = fetchFromGitHub {
    owner  = "tembo-io";
    repo   = pname;
    rev    = "v${version}";
    hash = "sha256-z+8/BqIlHwlMnuIzMz6eylmYbSmhtsNt7TJf/CxbdVw=";
  };

  buildPhase = ''
    cd pgmq-extension
  '';

  installPhase = ''
    mkdir -p $out/{lib,share/postgresql/extension}

    mv sql/pgmq.sql $out/share/postgresql/extension/pgmq--${version}.sql
    cp sql/*.sql $out/share/postgresql/extension
    cp *.control $out/share/postgresql/extension
  '';

  meta = with lib; {
    description = "A lightweight message queue. Like AWS SQS and RSMQ but on Postgres.";
    homepage    = "https://github.com/tembo-io/pgmq";
    maintainers = with maintainers; [ olirice ];
    platforms   = postgresql.meta.platforms;
    license     = licenses.postgresql;
  };
}
