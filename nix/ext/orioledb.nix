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
    rev = "18a3029046ce70464d22bff6398885fa705aa54d";
    sha256 = "sha256-tIXg/jp6yNkfw9KHxFpR55LXaA2tvv1LY1/sOxhSqkA=";
  };
  version = "18a3029046ce70464d22bff6398885fa705aa54d";
  buildInputs = [
    curl
    libkrb5
    postgresql
    python3
    openssl
  ];
  buildPhase = ''
    make USE_PGXS=1 ORIOLEDB_PATCHSET_VERSION=07eed1c01c0b649922c822867f11c7a0ccd9e851
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
