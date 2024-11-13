{ lib, stdenv, fetchFromGitHub, postgresql, flex, openssl, libkrb5 }:

stdenv.mkDerivation rec {
  pname = "pg_tle";
  version = "1.4.0";

  nativeBuildInputs = [ flex ];
  buildInputs = [ openssl postgresql libkrb5 ];

  src = fetchFromGitHub {
    owner = "aws";
    repo = pname;
    rev = "refs/tags/v${version}";
    hash = "sha256-crxj5R9jblIv0h8lpqddAoYe2UqgUlnvbOajKTzVces=";
  };

  
  makeFlags = [ "FLEX=flex" ];

  
  installPhase = ''
    mkdir -p $out/{lib,share/postgresql/extension}

    cp *${postgresql.dlSuffix}      $out/lib
    cp *.sql     $out/share/postgresql/extension
    cp *.control $out/share/postgresql/extension
  '';

  meta = with lib; {
    description = "Framework for 'Trusted Language Extensions' in PostgreSQL";
    homepage = "https://github.com/aws/${pname}";
    maintainers = with maintainers; [ samrose ];
    platforms = postgresql.meta.platforms;
    license = licenses.postgresql;
  };
}
