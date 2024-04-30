{ lib, stdenv, fetchFromGitHub, postgresql }:

stdenv.mkDerivation rec {
  pname = "supautils";
  version = "2.2.1-test-pg16";

  buildInputs = [ postgresql ];

  src = fetchFromGitHub {
    owner = "supabase";
    repo = pname;
    rev = "refs/tags/v${version}";
    hash = "sha256-cm0Ya/j9YR1Owv56EifPZwrXrqR4sZlyCKiW93LrE30=";
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
