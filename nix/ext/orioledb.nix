{ lib, stdenv, fetchFromGitHub, curl, libkrb5, postgresql, python3, openssl }:

stdenv.mkDerivation rec {
  pname = "orioledb";
  name = pname;
  src = fetchFromGitHub {
    owner = "orioledb";
    repo = "orioledb";
    rev = "main";
    sha256 = "sha256-VWjb2JHYad0VZkId70m8UOhRTJRGY4nkEuC7m5ae7w4=";
  };
  version = "patches16_29";
  buildInputs = [ curl libkrb5 postgresql python3 openssl ];
  buildPhase = "make USE_PGXS=1 ORIOLEDB_PATCHSET_VERSION=29";
  installPhase = ''
    runHook preInstall
    mkdir -p $out/{lib,share/postgresql/extension}

    cp *.so      $out/lib
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
