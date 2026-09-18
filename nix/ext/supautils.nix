{
  lib,
  stdenv,
  fetchFromGitHub,
  postgresql,
  patchelf,
}:

stdenv.mkDerivation rec {
  pname = "supautils";
  name = pname;
  version = "3.4.3";

  buildInputs = [ postgresql ];
  nativeBuildInputs = lib.optionals stdenv.isLinux [ patchelf ];

  separateDebugInfo = true;
  NIX_DONT_SET_RPATH = stdenv.isLinux;

  __structuredAttrs = true;
  unsafeDiscardReferences.out = stdenv.isLinux;

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
  ''
  + lib.optionalString stdenv.isLinux ''
    patchelf --remove-rpath $out/lib/supautils${postgresql.dlSuffix}
  '';

  meta = with lib; {
    description = "PostgreSQL extension for enhanced security";
    homepage = "https://github.com/supabase/${pname}";
    platforms = postgresql.meta.platforms;
    license = licenses.postgresql;
  };
}
