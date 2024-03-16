{ lib, stdenv, fetchFromGitHub, postgresql }:

stdenv.mkDerivation rec {
  pname = "pg_plan_filter";
  version = "unstable-2021-09-23";

  buildInputs = [ postgresql ];

  src = fetchFromGitHub {
    owner = "pgexperts";
    repo = pname;
    rev = "5081a7b5cb890876e67d8e7486b6a64c38c9a492";
    hash = "sha256-YNeIfmccT/DtOrwDmpYFCuV2/P6k3Zj23VWBDkOh6sw=";
  };

  installPhase = ''
    mkdir -p $out/{lib,share/postgresql/extension}

    cp *.so      $out/lib
    cp *.sql     $out/share/postgresql/extension
  '';

  meta = with lib; {
    description = "Filter PostgreSQL statements by execution plans";
    homepage = "https://github.com/pgexperts/${pname}";
    maintainers = with maintainers; [ thoughtpolice ];
    platforms = postgresql.meta.platforms;
    license = licenses.postgresql;
  };
}
