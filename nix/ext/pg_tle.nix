{ lib, stdenv, fetchFromGitHub, postgresql, flex }:

stdenv.mkDerivation rec {
  pname = "pg_tle";
  version = "1.0.4";

  nativeBuildInputs = [ flex ];
  buildInputs = [ postgresql ];

  src = fetchFromGitHub {
    owner = "aws";
    repo = pname;
    rev = "refs/tags/v${version}";
    hash = "sha256-W/7pLy/27VatCdzUh1NZ4K2FRMD1erfHiFV2eY2x2W0=";
  };

  makeFlags = [ "FLEX=flex" ];

  installPhase = ''
    mkdir -p $out/{lib,share/postgresql/extension}

    cp *.so      $out/lib
    cp *.sql     $out/share/postgresql/extension
    cp *.control $out/share/postgresql/extension
  '';

  meta = with lib; {
    description = "Framework for 'Trusted Language Extensions' in PostgreSQL";
    homepage = "https://github.com/aws/${pname}";
    maintainers = with maintainers; [ thoughtpolice ];
    platforms = postgresql.meta.platforms;
    license = licenses.postgresql;
  };
}
