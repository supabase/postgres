{
  lib,
  stdenv,
  fetchFromGitHub,
  postgresql,
}:

stdenv.mkDerivation rec {
  pname = "supautils";
  version = "3.0.2";

  buildInputs = [ postgresql ];

  src = fetchFromGitHub {
    owner = "supabase";
    repo = pname;
    rev = "refs/tags/v${version}";
    hash = "sha256-WTLZShBFVgb18vVi15TSZvtJrNUFgQa6mBkavvRSoUE=";
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
