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
    rev = "beta12";
    sha256 = "sha256-5dyVdKD1PzW+F5OPW3TR3OKBaJxxR3OhLbzK+o9Wf+Q=";
  };
  version = "beta12";
  buildInputs = [
    curl
    libkrb5
    postgresql
    python3
    openssl
  ];
  buildPhase = "make USE_PGXS=1 ORIOLEDB_PATCHSET_VERSION=11";
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
