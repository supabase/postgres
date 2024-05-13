{ lib, stdenv, fetchFromGitHub, postgresql }:

stdenv.mkDerivation rec {
  pname = "pgvector";
  version = "0.7.0";

  buildInputs = [ postgresql ];

  src = fetchFromGitHub {
    owner = "pgvector";
    repo = pname;
    rev = "refs/tags/v${version}";
    hash = "sha256-vFn7sNphOYyig6Jl1HILMaC2t9strFQBQ8ywL8Ibx1M=";
  };

  installPhase = ''
    mkdir -p $out/{lib,share/postgresql/extension}

    cp *.so      $out/lib
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
