{
  lib,
  stdenv,
  fetchFromGitHub,
  postgresql,
}:

stdenv.mkDerivation rec {
  pname = "supautils";
  name = pname;
  version = "4.0.0";

  buildInputs = [ postgresql ];

  separateDebugInfo = true;

  # dlopen'd into postgres, which already links these libs
  NIX_DONT_SET_RPATH = stdenv.isLinux;

  src = fetchFromGitHub {
    owner = "supabase";
    repo = pname;
    rev = "refs/tags/v${version}";
    hash = "sha256-2tH34+JdgNqaR5ihtdJJQSIdT7zI4NTRHlYuEEO6/f8=";
  };

  # remove once all Ubuntu 20.04 (glibc 2.31) hosts are decommissioned
  patches = [ ./patches/supautils-strtol-glibc-compat.patch ];

  installPhase = ''
    mkdir -p $out/lib/postgresql

    install -D *${postgresql.dlSuffix} -t $out/lib
    ln -s ../supautils${postgresql.dlSuffix} $out/lib/postgresql/supautils${postgresql.dlSuffix}
  '';

  meta = with lib; {
    description = "PostgreSQL extension for enhanced security";
    homepage = "https://github.com/supabase/${pname}";
    platforms = postgresql.meta.platforms;
    license = licenses.postgresql;
  };
}
