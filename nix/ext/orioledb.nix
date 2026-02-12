{
  lib,
  stdenv,
  fetchFromGitHub,
  curl,
  libkrb5,
  postgresql,
  python3,
  openssl,
}:

stdenv.mkDerivation rec {
  pname = "orioledb";
  name = pname;
  src = fetchFromGitHub {
    owner = "orioledb";
    repo = "orioledb";
    rev = "00043a2881d0d2a3dfe7914e2a67694889c686b5";
    sha256 = "sha256-Vz3vfmTGRW+O9aXZxqixHC2CpqZJf/1UCQWoENbAak4=";
  };
  version = "00043a2881d0d2a3dfe7914e2a67694889c686b5";
  buildInputs = [
    curl
    libkrb5
    postgresql
    python3
    openssl
  ];
  buildPhase = ''
    make USE_PGXS=1 ORIOLEDB_PATCHSET_VERSION=16
  '';
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
    platforms = postgresql.meta.platforms;
    license = licenses.postgresql;
  };
}
