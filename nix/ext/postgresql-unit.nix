{ lib, stdenv, fetchFromGitHub, postgresql, flex, bison }:

stdenv.mkDerivation rec {
  pname = "postgresql-unit";
  version = "7.10";
  name = "postgresql-unit";
  buildInputs = [ postgresql ];
  nativeBuildInputs = [ flex bison ];

  src = fetchFromGitHub {
    owner = "df7cb";
    repo = pname;
    rev = "${version}";
    hash = "sha256-glVyW0n34I3QArlTscV+p1/sfhIfFbeH192rf9uYJp0=";
  };


  installPhase = ''
    mkdir -p $out/{lib,share/postgresql/extension}

    # Fix the @MODULEDIR@ / postgresql path reference
    substituteInPlace *.sql \
      --replace "${postgresql}/share/postgresql/extension/" "$out/share/postgresql/extension/"

    cp *.so $out/lib
    cp *.sql $out/share/postgresql/extension
    cp *.data $out/share/postgresql/extension
    cp *.control $out/share/postgresql/extension

  '';

  meta = with lib; {
    description = "Unit testing framework for PostgreSQL";
    homepage = "https://github.com/${src.owner}/${src.repo}";
    maintainers = [ "df7cb" ];
    platforms = postgresql.meta.platforms;
    license = licenses.postgresql;
  };
}
