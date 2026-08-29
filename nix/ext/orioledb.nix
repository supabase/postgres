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
    rev = "657812f526d732417630bd4355fb6be28a72321b";
    sha256 = "sha256-NzAk1wrWL89tUxvHJ/P2W2Sh4HxeJ0Kvw2lQQN1bRqY=";
  };
  version = "657812f526d732417630bd4355fb6be28a72321b";
  buildInputs = [
    curl
    libkrb5
    postgresql
    python3
    openssl
  ];
  buildPhase = ''
    make USE_PGXS=1 ORIOLEDB_PATCHSET_VERSION=b8970548a74d2adec467ce7c99469a34edbc563b
  '';
  separateDebugInfo = true;
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
