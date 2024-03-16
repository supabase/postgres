{ lib, curl, lz4, zstd, krb5, icu, stdenv, fetchFromGitHub, postgresql }:
#FIXME we have decided deactivate this for now, as it is not used in production
# if we decide to use it later we may need to look at this documentation 
# https://docs.citusdata.com/en/stable/admin_guide/upgrading_citus.html#upgrading-postgresql-version-from-15-to-16
stdenv.mkDerivation rec {
  pname = "citus";
  version = "12.1.2";

  buildInputs = [ curl lz4 zstd krb5 icu.dev postgresql ];

  src = fetchFromGitHub {
    owner = "citusdata";
    repo = pname;
    rev = "refs/tags/v${version}";
    hash = "sha256-0uYNMLAYigtGlDRvOEkQeC5i58QfXcdSVjTQwWVFX+8=";
  };

  installPhase = ''
    mkdir -p $out/{lib,share/postgresql/extension}

    cp src/backend/columnar/citus_columnar.so      $out/lib
    cp src/backend/columnar/citus_columnar.control $out/share/postgresql/extension
    cp src/backend/columnar/build/sql/*.sql        $out/share/postgresql/extension

    cp src/backend/distributed/citus.so            $out/lib
    cp src/backend/distributed/citus.control       $out/share/postgresql/extension
    cp src/backend/distributed/build/sql/*.sql     $out/share/postgresql/extension
  '';

  meta = with lib; {
    description = "Distributed PostgreSQL as an extension";
    homepage = "https://github.com/citusdata/${pname}";
    maintainers = with maintainers; [ olirice ];
    platforms = postgresql.meta.platforms;
    license = licenses.agpl3Plus;
  };
}
