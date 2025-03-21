{ lib, stdenv, fetchFromGitHub, postgresql }:

stdenv.mkDerivation rec {
  pname = "pg_plan_filter";
  version = "5081a7b5cb890876e67d8e7486b6a64c38c9a492";

  buildInputs = [ postgresql ];

  src = fetchFromGitHub {
    owner = "pgexperts";
    repo = pname;
    rev = "${version}";
    hash = "sha256-YNeIfmccT/DtOrwDmpYFCuV2/P6k3Zj23VWBDkOh6sw=";
  };

  installPhase = ''
    mkdir -p $out/{lib,share/postgresql/extension}

    cp *${postgresql.dlSuffix}      $out/lib
    cp *.sql     $out/share/postgresql/extension
  '';

  meta = with lib; {
    description = "Filter PostgreSQL statements by execution plans";
    homepage = "https://github.com/pgexperts/${pname}";
    platforms = postgresql.meta.platforms;
    license = licenses.postgresql;
  };
}
