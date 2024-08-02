{ lib, stdenv, fetchFromGitHub, postgresql }:

stdenv.mkDerivation rec {
  pname = "pg_backtrace";
  version = "1.7.0";

  buildInputs = [ postgresql ];

  src = fetchFromGitHub {
    owner  = "pashkinelfe";
    repo   = pname;
    rev    = "59478e9b42676b5cdfda281ec9a3dc7a7a49228c";
    hash = "sha256-g4DrbMsZiL/cjxz0OxerAo/rRgcekKb3RgsDwOQpqRs=";
  };

  makeFlags = [ "USE_PGXS=1" ];

  installPhase = ''
    mkdir -p $out/{lib,share/postgresql/extension}

    cp *.so      $out/lib
    cp *.sql     $out/share/postgresql/extension
    cp *.control $out/share/postgresql/extension
  '';

  meta = with lib; {
    description = "Updated fork of pg_backtrace";
    homepage    = "https://github.com/pashkinelfe/pg_backtrace";
    maintainers = with maintainers; [ samrose ];
    platforms   = postgresql.meta.platforms;
    license     = licenses.postgresql;
  };
}
