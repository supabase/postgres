{
  lib,
  stdenv,
  fetchFromGitHub,
  postgresql,
}:

stdenv.mkDerivation rec {
  pname = "supautils";
  name = pname;
  version = "3.0.1";

  buildInputs = [ postgresql ];

  src = fetchFromGitHub {
    owner = "supabase";
    repo = pname;
    rev = "refs/tags/v${version}";
    hash = "sha256-j0iASDzmcZRLbHaS9ZNRWwzii7mcC+8wYHM0/mOLkbs=";
  };

  installPhase = ''
    mkdir -p $out/lib

    install -D *${postgresql.dlSuffix} -t $out/lib
  '';

  meta = with lib; {
    description = "PostgreSQL extension for enhanced security";
    homepage = "https://github.com/supabase/${pname}";
    maintainers = with maintainers; [ steve-chavez ];
    platforms = postgresql.meta.platforms;
    license = licenses.postgresql;
  };
}
