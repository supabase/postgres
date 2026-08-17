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
    rev = "94e1d3c9a873fb7c132d4683cce0753f7f08142c";
    sha256 = "sha256-hxUU8H9PEpEhBuRCh/yvjjSmONnMKTstlQB/pK7Sc1s=";
  };
  version = "94e1d3c9a873fb7c132d4683cce0753f7f08142c";
  buildInputs = [
    curl
    libkrb5
    postgresql
    python3
    openssl
  ];
  buildPhase = ''
    make USE_PGXS=1 ORIOLEDB_PATCHSET_VERSION=1e13fa1993dd9b1b867e6362c1f1930849e8be7b
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
