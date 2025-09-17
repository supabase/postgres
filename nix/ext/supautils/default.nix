{
  lib,
  stdenv,
  fetchFromGitHub,
  postgresql,
}:

stdenv.mkDerivation rec {
  pname = "supautils";
  version = "2.10.0";

  buildInputs = [ postgresql ];

  src = fetchFromGitHub {
    owner = "supabase";
    repo = pname;
    rev = "refs/tags/v${version}";
    hash = "sha256-jhTLC7aoodjHl98nnKxh6TuznrCg28/6b++6OM05WIs=";
  };

  # Fix PostgreSQL 18 compatibility by making log_skipped_evtrigs static
  postPatch = lib.optionalString (lib.versionAtLeast postgresql.version "18") ''
    sed -i 's/^bool log_skipped_evtrigs = false;/static bool log_skipped_evtrigs = false;/' src/supautils.c
  '';

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
