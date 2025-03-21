{ lib, stdenv, fetchFromGitHub, libsodium, postgresql }:

stdenv.mkDerivation rec {
  pname = "pgsodium";
  version = "3.1.8";

  buildInputs = [ libsodium postgresql ];

  src = fetchFromGitHub {
    owner = "michelp";
    repo = pname;
    rev = "refs/tags/v${version}";
    hash = "sha256-j5F1PPdwfQRbV8XJ8Mloi8FvZF0MTl4eyIJcBYQy1E4=";
  };

  installPhase = ''
    mkdir -p $out/{lib,share/postgresql/extension}

    cp *${postgresql.dlSuffix}      $out/lib
    cp sql/*.sql $out/share/postgresql/extension
    cp *.control $out/share/postgresql/extension
  '';

  meta = with lib; {
    description = "Modern cryptography for PostgreSQL";
    homepage = "https://github.com/michelp/${pname}";
    platforms = postgresql.meta.platforms;
    license = licenses.postgresql;
  };
}
