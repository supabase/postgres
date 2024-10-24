{ lib, stdenv, fetchFromGitHub, curl, libkrb5, postgresql, python3, openssl }:

stdenv.mkDerivation rec {
  pname = "orioledb";
  name = pname;
  src = fetchFromGitHub {
    owner = "orioledb";
    repo = "orioledb";
    rev = "bd8e32d0ebaafd0ea3ec3074233b65167f3b6fb7";
    sha256 = "sha256-bzH1SgPZ6q90HpqRsECY2XQPghEcd2Hg4X55G43unNo=";
  };
  version = "patches16_31";
  buildInputs = [ curl libkrb5 postgresql python3 openssl ];
  buildPhase = "make USE_PGXS=1 ORIOLEDB_PATCHSET_VERSION=31";
  installPhase = ''
    runHook preInstall
    mkdir -p $out/{lib,share/postgresql/extension}

    cp *${postgresql.dlSuffix}      $out/lib
    cp *.sql     $out/share/postgresql/extension
    cp *.control $out/share/postgresql/extension
        
    runHook postInstall
  '';
  doCheck = true;
  meta = with lib; {
    description = "orioledb";
    maintainers = with maintainers; [ samrose ];
    platforms = postgresql.meta.platforms;
    license = licenses.postgresql;
  };
}
