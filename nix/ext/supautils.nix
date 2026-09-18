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
    so=$out/lib/supautils${postgresql.dlSuffix}
    rp=$(patchelf --print-rpath "$so")
    patchelf --remove-rpath "$so"
    if [ -n "$rp" ]; then
      off=$(grep -aboF "$rp" "$so" | head -1 | cut -d: -f1)
      dd if=/dev/zero of="$so" bs=1 seek="$off" count="''${#rp}" conv=notrunc status=none
    fi
  '';

  meta = with lib; {
    description = "PostgreSQL extension for enhanced security";
    homepage = "https://github.com/supabase/${pname}";
    platforms = postgresql.meta.platforms;
    license = licenses.postgresql;
  };
}
