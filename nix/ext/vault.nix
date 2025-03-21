{ lib, stdenv, fetchFromGitHub, libsodium, postgresql }:

stdenv.mkDerivation rec {
  pname = "vault";
  version = "0.3.1";

  buildInputs = [ libsodium postgresql ];

  src = fetchFromGitHub {
    owner = "supabase";
    repo = pname;
    rev = "refs/tags/v${version}";
    hash = "sha256-MC87bqgtynnDhmNZAu96jvfCpsGDCPB0g5TZfRQHd30=";
  };

  installPhase = ''
    mkdir -p $out/{lib,share/postgresql/extension}

    install -D *${postgresql.dlSuffix} $out/lib
    install -D -t $out/share/postgresql/extension sql/*.sql
    install -D -t $out/share/postgresql/extension *.control
  '';

  meta = with lib; {
    description = "Store encrypted secrets in PostgreSQL";
    homepage = "https://github.com/supabase/${pname}";
    platforms = postgresql.meta.platforms;
    license = licenses.postgresql;
  };
}
