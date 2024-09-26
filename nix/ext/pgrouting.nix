{ lib, stdenv, fetchFromGitHub, postgresql, perl, cmake, boost }:
let
  source = {
    "16" = {
      version = "3.6.2";
      hash = "sha256-r+OkhieKTiOfYSnDbiy3p8V8cgb8I1+bneFwItDfDYo=";
    };
    "15" = {
      version = "3.4.1";
      hash = "sha256-QC77AnPGpPQGEWi6JtJdiNsB2su5+aV2pKg5ImR2B0k=";
    };
  }.${lib.versions.major postgresql.version} or (throw "Source for pgrouting is not available for ${postgresql.version}");
in

stdenv.mkDerivation rec {
  pname = "pgrouting";
  inherit (source) version;

  nativeBuildInputs = [ cmake perl ];
  buildInputs = [ postgresql boost ];

  src = fetchFromGitHub {
    owner  = "pgRouting";
    repo   = pname;
    rev    = "v${source.version}";
    hash = source.hash;
  };

  installPhase = ''
    install -D lib/*.so                        -t $out/lib
    install -D sql/pgrouting--${version}.sql   -t $out/share/postgresql/extension
    install -D sql/common/pgrouting.control    -t $out/share/postgresql/extension
  '';

  meta = with lib; {
    description = "A PostgreSQL/PostGIS extension that provides geospatial routing functionality";
    homepage    = "https://pgrouting.org/";
    changelog   = "https://github.com/pgRouting/pgrouting/releases/tag/v${version}";
    maintainers = with maintainers; [ steve-chavez samrose ];
    platforms   = postgresql.meta.platforms;
    license     = licenses.gpl2Plus;
  };
}
