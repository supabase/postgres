{ lib, stdenv, fetchFromGitHub, curl, libkrb5, postgresql, python3, openssl }:

stdenv.mkDerivation rec {
  pname = "orioledb";
  name = pname;
  src = fetchFromGitHub {
    owner = "orioledb";
    repo = "orioledb";
    rev = "beta9";
    sha256 = "sha256-z2EHWsY+hhtnYzAxOl2PWjqfyJ+wp9SCau5LKPT2ec0=";
  };
  version = "beta9";
  buildInputs = [ curl libkrb5 postgresql python3 openssl ];
  buildPhase = "make USE_PGXS=1 ORIOLEDB_PATCHSET_VERSION=5";
  installPhase = ''
    runHook preInstall
    
    mkdir -p $out/{lib,share/postgresql/extension}

    # Copy the extension library
    cp orioledb${postgresql.dlSuffix} $out/lib/
    
    # Copy sql files from the sql directory
    cp sql/*.sql $out/share/postgresql/extension/
    
    # Copy control file
    cp orioledb.control $out/share/postgresql/extension/
        
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
