{ lib, stdenv, fetchFromGitHub, postgresql }:

stdenv.mkDerivation rec {
  pname = "hypopg";
  version = "1.3.1";

  buildInputs = [ postgresql ];

  src = fetchFromGitHub {
    owner = "HypoPG";
    repo = pname;
    rev = "refs/tags/${version}";
    hash = "sha256-AIBXy+LxyHUo+1hd8gQTwaBdFiTEzKaCVc4cx5tZgME=";
  };

  installPhase = ''
    mkdir -p $out/{lib,share/postgresql/extension}

    cp *.so      $out/lib
    cp *.sql     $out/share/postgresql/extension
    cp *.control $out/share/postgresql/extension
  '';

  meta = with lib; {
    description = "Hypothetical Indexes for PostgreSQL";
    homepage = "https://github.com/HypoPG/${pname}";
    maintainers = with maintainers; [ samrose ];
    platforms = postgresql.meta.platforms;
    license = licenses.postgresql;
  };
}
