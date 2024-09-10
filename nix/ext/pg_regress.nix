{ lib
, stdenv
, postgresql
}:

stdenv.mkDerivation {
  pname = "pg_regress";
  version = "0.0.1";

  phases = [ "installPhase" ];

  installPhase = ''
    mkdir -p $out/bin
    cp ${postgresql}/lib/pgxs/src/test/regress/pg_regress $out/bin/
  '';

  meta = with lib; {
    description = "Regression testing tool for PostgreSQL";
    homepage = "https://www.postgresql.org/";
    maintainers = with maintainers; [ samrose ];
    platforms = postgresql.meta.platforms;
    license = licenses.postgresql;
  };
}
