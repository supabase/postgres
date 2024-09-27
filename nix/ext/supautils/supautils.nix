{ lib, stdenv, fetchFromGitHub, postgresql }:

stdenv.mkDerivation rec {
  pname = "supautils";
  version = "2.2.1";

  buildInputs = [ postgresql ];

  src = fetchFromGitHub {
    owner = "supabase";
    repo = pname;
    rev = "c10c4d5525828950aaf4356d77881afe55b2fd10";
    hash = "sha256-P/vZBgZWI0HFqo2S88vCiOBGtVhy3S8NIIXOHgLEdKc=";
  };

  #patches = [ ./pg17.patch ];

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