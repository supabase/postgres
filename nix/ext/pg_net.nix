{ lib, stdenv, fetchFromGitHub, curl, postgresql }:

stdenv.mkDerivation rec {
  pname = "pg_net";
  version = "0.8.0";

  buildInputs = [ curl postgresql ];

  src = fetchFromGitHub {
    owner = "supabase";
    repo = pname;
    rev = "refs/tags/v${version}";
    hash = "sha256-ZPsRPWV1G3lMM2mT+H139Wvgoy8QnmeUbzEnGeDJmZA=";
  };

  env.NIX_CFLAGS_COMPILE = "-Wno-error";

  installPhase = ''
    mkdir -p $out/{lib,share/postgresql/extension}

    cp *.so      $out/lib
    cp sql/*.sql $out/share/postgresql/extension
    cp *.control $out/share/postgresql/extension
  '';

  meta = with lib; {
    description = "Async networking for Postgres";
    homepage = "https://github.com/supabase/pg_net";
    maintainers = with maintainers; [ samrose ];
    platforms = postgresql.meta.platforms;
    license = licenses.postgresql;
  };
}
