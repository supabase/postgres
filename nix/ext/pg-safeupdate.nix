{ lib, stdenv, fetchFromGitHub, postgresql }:

stdenv.mkDerivation rec {
  pname = "pg-safeupdate";
  version = "1.4";

  buildInputs = [ postgresql ];

  src = fetchFromGitHub {
    owner  = "eradman";
    repo   = pname;
    rev    = version;
    hash = "sha256-1cyvVEC9MQGMr7Tg6EUbsVBrMc8ahdFS3+CmDkmAq4Y=";
  };

  installPhase = ''
    install -D safeupdate${postgresql.dlSuffix} -t $out/lib
  '';

  meta = with lib; {
    description = "A simple extension to PostgreSQL that requires criteria for UPDATE and DELETE";
    homepage    = "https://github.com/eradman/pg-safeupdate";
    changelog   = "https://github.com/eradman/pg-safeupdate/raw/${src.rev}/NEWS";
    platforms   = postgresql.meta.platforms;
    license     = licenses.postgresql;
    broken      = versionOlder postgresql.version "14";
    maintainers = with maintainers; [ samrose ];
  };
}
