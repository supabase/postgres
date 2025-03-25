{ lib, stdenv, fetchFromGitHub, postgresql, libmysqlclient }:

stdenv.mkDerivation ( finalAttrs: {
  pname = "mysql_fdw";
  version = "REL-2_9_2";

  buildInputs = [ postgresql libmysqlclient ];

  src = fetchFromGitHub {
    owner = "EnterpriseDB";
    repo = finalAttrs.pname;
    rev = "refs/tags/${finalAttrs.version}";
    sha256 = "sha256-CLnSaV+pv+i/k1RlFmMVMK9hXWQkJvEim/xYghXv2cs=";
  };

  preConfigure = ''
    export NIX_LDFLAGS="-L${libmysqlclient}/lib/mariadb -lmysqlclient"
  '';

  makeFlags = [
    "USE_PGXS=1"
    "LDFLAGS+=-L${libmysqlclient}/lib/mariadb -lmysqlclient"
    "CPPFLAGS=-I${libmysqlclient}/include/mysql"
  ];

  installPhase = ''
    mkdir -p $out/{lib,share/postgresql/extension}
    
    cp *${postgresql.dlSuffix}      $out/lib
    cp *.sql     $out/share/postgresql/extension
    cp *.control $out/share/postgresql/extension
    cp *.config  $out/share/postgresql/extension
  '';

  postInstall = ''
    # Ensure mysql_fdw.so finds the correct libmysqlclient.so path
    patchelf --set-rpath ${libmysqlclient}/lib/mariadb $out/lib/mysql_fdw.so
  '';

  meta = with lib; {
    description = "MySQL foreign data wrapper for PostgreSQL";
    homepage    = "https://github.com/EnterpriseDB/mysql_fdw";
    changelog   = "https://github.com/EnterpriseDB/mysql_fdw/releases/tags/${finalAttrs.version}";
    maintainers = with maintainers; [ thelazzziest ];
    inherit (postgresql.meta) platforms;
    license     = licenses.postgresql;
  };
})
