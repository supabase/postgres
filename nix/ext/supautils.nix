{
  lib,
  stdenv,
  fetchFromGitHub,
  postgresql,
}:

stdenv.mkDerivation rec {
  pname = "supautils";
  name = pname;
  version = "3.4.4";

  buildInputs = [ postgresql ];

  src = fetchFromGitHub {
    owner = "supabase";
    repo = pname;
    rev = "refs/tags/v${version}";
    hash = "sha256-Wsou5U7/Tuwj2E6aPEmlHg7uz7kGyBOGrb7UkjfEo9U=";
  };

  installPhase = ''
    mkdir -p $out/lib

    install -D *${postgresql.dlSuffix} -t $out/lib
  '';

  meta = with lib; {
    description = "PostgreSQL extension for enhanced security";
    homepage = "https://github.com/supabase/${pname}";
    platforms = postgresql.meta.platforms;
    license = licenses.postgresql;
  };
}
