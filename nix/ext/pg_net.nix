{
  lib,
  stdenv,
  fetchFromGitHub,
  curl,
  postgresql,
}:

stdenv.mkDerivation rec {
  pname = "pg_net";
  version = "0.19.5";

  buildInputs = [
    curl
    postgresql
  ];

  src = fetchFromGitHub {
    owner = "supabase";
    repo = pname;
    rev = "refs/tags/v${version}";
    hash = "sha256-Cpi2iASi1QJoED0Qs1dANqg/BNZTsz5S+pw8iYyW03Y=";
  };

  installPhase = ''
    mkdir -p $out/{lib,share/postgresql/extension}

    cp *${postgresql.dlSuffix}      $out/lib
    cp sql/*.sql $out/share/postgresql/extension
    cp *.control $out/share/postgresql/extension
  '';

  meta = with lib; {
    description = "Async networking for Postgres";
    homepage = "https://github.com/supabase/pg_net";
    platforms = postgresql.meta.platforms;
    license = licenses.postgresql;
  };
}
