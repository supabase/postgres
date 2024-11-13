{ lib, stdenv, fetchFromGitHub, postgresql }:

stdenv.mkDerivation rec {
  pname = "pgvector";
  version = "0.8.0";

  buildInputs = [ postgresql ];

  src = fetchFromGitHub {
    owner = "pgvector";
    repo = pname;
    rev = "refs/tags/v${version}";
    hash = "sha256-JsZV+I4eRMypXTjGmjCtMBXDVpqTIPHQa28ogXncE/Q=";
  };

  installPhase = ''
    mkdir -p $out/{lib,share/postgresql/extension}

    cp *${postgresql.dlSuffix}      $out/lib
    cp sql/*.sql $out/share/postgresql/extension
    cp *.control $out/share/postgresql/extension
  '';

  meta = with lib; {
    description = "Open-source vector similarity search for Postgres";
    homepage = "https://github.com/${src.owner}/${src.repo}";
    maintainers = with maintainers; [ olirice ];
    platforms = postgresql.meta.platforms;
    license = licenses.postgresql;
  };
}
