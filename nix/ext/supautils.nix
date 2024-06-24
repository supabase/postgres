{ lib, stdenv, fetchFromGitHub, postgresql }:

stdenv.mkDerivation rec {
  pname = "supautils";
  version = "2.2.0";

  buildInputs = [ postgresql ];

  src = fetchFromGitHub {
    owner = "supabase";
    repo = pname;
    rev = "refs/tags/v${version}";
    hash = "sha256-LEMhUM0woTwRcSWOU70izS5eWevoV8nnMUOEID+Nsdc=";
  };

  installPhase = ''
    mkdir -p $out/lib

    install -D supautils.so -t $out/lib
  '';

  meta = with lib; {
    description = "PostgreSQL extension for enhanced security";
    homepage = "https://github.com/supabase/${pname}";
    maintainers = with maintainers; [ steve-chavez ];
    platforms = postgresql.meta.platforms;
    license = licenses.postgresql;
  };
}
