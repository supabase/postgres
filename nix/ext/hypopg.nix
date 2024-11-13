{ lib, stdenv, fetchFromGitHub, postgresql }:

stdenv.mkDerivation rec {
  pname = "hypopg";
  version = "1.4.1";

  buildInputs = [ postgresql ];

  src = fetchFromGitHub {
    owner = "HypoPG";
    repo = pname;
    rev = "refs/tags/${version}";
    hash = "sha256-88uKPSnITRZ2VkelI56jZ9GWazG/Rn39QlyHKJKSKMM=";
  };

  installPhase = ''
    mkdir -p $out/{lib,share/postgresql/extension}

    cp *${postgresql.dlSuffix}      $out/lib
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
