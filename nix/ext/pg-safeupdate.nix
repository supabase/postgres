{
  lib,
  stdenv,
  fetchFromGitHub,
  postgresql,
}:

stdenv.mkDerivation rec {
  pname = "pg-safeupdate";
  version = "1.4";

  buildInputs = [ postgresql ];

  src = fetchFromGitHub {
    owner = "eradman";
    repo = pname;
    rev = version;
    hash = "sha256-1cyvVEC9MQGMr7Tg6EUbsVBrMc8ahdFS3+CmDkmAq4Y=";
  };

  buildPhase = ''
    runHook preBuild
    make PG_CONFIG=${postgresql}/bin/pg_config
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    make install PG_CONFIG=${postgresql}/bin/pg_config DESTDIR=$out
    runHook postInstall
  '';

  meta = with lib; {
    description = "A simple extension to PostgreSQL that requires criteria for UPDATE and DELETE";
    homepage = "https://github.com/eradman/pg-safeupdate";
    platforms = postgresql.meta.platforms;
    license = licenses.postgresql;
  };
}
