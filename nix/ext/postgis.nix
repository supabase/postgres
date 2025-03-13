{ fetchurl
, lib, stdenv
, perl
, libxml2
, postgresql
, geos
, proj
, json_c
, pkg-config
, file
, protobufc
, libiconv
, pcre2
, nixosTests
, callPackage
}:

let
  sfcgal = callPackage ./sfcgal/sfcgal.nix { };
  gdal = callPackage ./gdal.nix { inherit postgresql; };
in
stdenv.mkDerivation rec {
  pname = "postgis";
  version = "3.3.7";

  outputs = [ "out" "doc" ];

  src = fetchurl {
    url = "https://download.osgeo.org/postgis/source/postgis-${version}.tar.gz";
    sha256 = "sha256-UHJKDd5JrcJT5Z4CTYsY/va+ToU0GUPG1eHhuXTkP84=";
  };

  buildInputs = [ libxml2 postgresql geos proj gdal json_c protobufc pcre2.dev sfcgal ]
                ++ lib.optional stdenv.isDarwin libiconv;
  nativeBuildInputs = [ perl pkg-config ];
  dontDisableStatic = true;


  env.NIX_LDFLAGS = "-L${lib.getLib json_c}/lib";

  preConfigure = ''
    sed -i 's@/usr/bin/file@${file}/bin/file@' configure
    configureFlags="--datadir=$out/share/postgresql --datarootdir=$out/share/postgresql --bindir=$out/bin --docdir=$doc/share/doc/${pname} --with-gdalconfig=${gdal}/bin/gdal-config --with-jsondir=${json_c.dev} --disable-extension-upgrades-install --with-sfcgal"

    makeFlags="PERL=${perl}/bin/perl datadir=$out/share/postgresql pkglibdir=$out/lib bindir=$out/bin docdir=$doc/share/doc/${pname}"
  '';

  postConfigure = ''
    sed -i "s|@mkdir -p \$(DESTDIR)\$(PGSQL_BINDIR)||g ;
            s|\$(DESTDIR)\$(PGSQL_BINDIR)|$prefix/bin|g
            " \
        "raster/loader/Makefile";
    sed -i "s|\$(DESTDIR)\$(PGSQL_BINDIR)|$prefix/bin|g
            " \
        "raster/scripts/python/Makefile";
    mkdir -p $out/bin
    ln -s ${postgresql}/bin/postgres $out/bin/postgres
  '';

postInstall = ''
  rm $out/bin/postgres
  for prog in $out/bin/*; do # */
    ln -s $prog $prog-${version}
  done
  # Add function definition and usage to tiger geocoder files
  for file in $out/share/postgresql/extension/postgis_tiger_geocoder*--${version}.sql; do
      sed -i "/SELECT postgis_extension_AddToSearchPath('tiger');/a SELECT postgis_extension_AddToSearchPath('extensions');" "$file"
  done
  # Original topology patching
  for file in $out/share/postgresql/extension/postgis_topology*--${version}.sql; do
    sed -i "/SELECT topology.AddToSearchPath('topology');/i SELECT topology.AddToSearchPath('extensions');" "$file"
  done
  mkdir -p $doc/share/doc/postgis
  mv doc/* $doc/share/doc/postgis/
'';

  passthru.tests.postgis = nixosTests.postgis;

  meta = with lib; {
    description = "Geographic Objects for PostgreSQL";
    homepage = "https://postgis.net/";
    changelog = "https://git.osgeo.org/gitea/postgis/postgis/raw/tag/${version}/NEWS";
    license = licenses.gpl2;
    maintainers = with maintainers; [ samrose ];
    inherit (postgresql.meta) platforms;
  };
}
