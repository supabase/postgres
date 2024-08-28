{ lib, stdenv, fetchFromGitHub, curl, postgresql }:

stdenv.mkDerivation rec {
  pname = "pg_net";
  version = "0.10.0";

  buildInputs = [ curl postgresql ];

  src = fetchFromGitHub {
    owner = "supabase";
    repo = pname;
    rev = "refs/tags/v${version}";
    hash = "sha256-R9Mzw5gvV7b2R59LTOzuOc0AI99+3ncFNzijI4mySUg=";
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
