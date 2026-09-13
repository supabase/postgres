{
  lib,
  stdenv,
  fetchFromGitHub,
  postgresql,
}:

stdenv.mkDerivation rec {
  pname = "supautils";
  name = pname;
  version = "3.4.3";

  buildInputs = [ postgresql ];

  dontStrip = true;

  src = fetchFromGitHub {
    owner = "supabase";
    repo = pname;
    rev = "refs/tags/v${version}";
    hash = "sha256-aCOQY6eNA7KgiEWtQoYpSHbJWwSnrcUPMm57RcesqKY=";
  };

  patches = [ ./patches/supautils-strtol-glibc-compat.patch ];

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
