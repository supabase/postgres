{ lib, stdenv, fetchFromGitHub, postgresql }:

stdenv.mkDerivation rec {
  pname = "pg_backtrace";
  version = "1.0";

  buildInputs = [ postgresql ];

  src = fetchFromGitHub {
    owner  = "pashkinelfe";
    repo   = pname;
    rev    = "fddeeb4ae0a8aa8993336463ef0d5fcd5b4b7cfd";
    hash = "sha256-o3bgPckh5KMHBgSiEmhmFSibbJzeIPOUTNyeLVh6Pkk=";
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
