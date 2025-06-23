{
  fetchurl,
  lib,
  stdenv,
  perl,
  libxml2,
  postgresql,
  geos,
  proj,
  json_c,
  pkg-config,
  file,
  protobufc,
  libiconv,
  pcre2,
  nixosTests,
  callPackage,
  buildEnv,
}:

let
  sfcgal = callPackage ./sfcgal/sfcgal.nix { };
  gdal = callPackage ./gdal.nix { inherit postgresql; };
  pname = "postgis";

  # Load version configuration from external file
  allVersions = (builtins.fromJSON (builtins.readFile ./versions.json)).${pname};

  # Filter versions compatible with current PostgreSQL version
  supportedVersions = lib.filterAttrs (
    _: value: builtins.elem (lib.versions.major postgresql.version) value.postgresql
  ) allVersions;

  # Derived version information
  versions = lib.naturalSort (lib.attrNames supportedVersions);
  latestVersion = lib.last versions;
  numberOfVersions = builtins.length versions;
  packages = builtins.attrValues (
    lib.mapAttrs (name: value: build name value.hash) supportedVersions
  );

  # List of C extensions to be included in the build
  cExtensions = [
    "address_standardizer"
    "postgis"
    "postgis_raster"
    "postgis_sfcgal"
    "postgis_topology"
  ];

  sqlExtensions = [
    "address_standardizer_data_us"
    "postgis_tiger_geocoder"
  ];

  # Build function for individual versions
  build =
    version: hash:
    stdenv.mkDerivation rec {
      inherit pname version;

      outputs = [
        "out"
        "doc"
      ];

      src = fetchurl {
        url = "https://download.osgeo.org/postgis/source/postgis-${version}.tar.gz";
        inherit hash;
      };

      buildInputs = [
        libxml2
        postgresql
        geos
        proj
        gdal
        json_c
        protobufc
        pcre2.dev
        sfcgal
      ] ++ lib.optional stdenv.isDarwin libiconv;
      nativeBuildInputs = [
        perl
        pkg-config
      ];
      dontDisableStatic = true;

      env.NIX_LDFLAGS = "-L${lib.getLib json_c}/lib";

      preConfigure = ''
        sed -i 's@/usr/bin/file@${file}/bin/file@' configure
        configureFlags="--datadir=$out/share/postgresql --datarootdir=$out/share/postgresql --bindir=$out/bin --docdir=$doc/share/doc/${pname} --with-gdalconfig=${gdal}/bin/gdal-config --with-jsondir=${json_c.dev} --with-sfcgal --with-library-minor-version"

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
        MIN_MAJ_VERSION=${lib.concatStringsSep "." (lib.take 2 (builtins.splitVersion version))}
        rm $out/bin/postgres

        # move control files
        for ext in ${lib.concatStringsSep " " (cExtensions ++ sqlExtensions)}; do
          sed -e "/^default_version =/d" \
              -e "s|^module_pathname = .*|module_pathname = '\$libdir/$ext'|" \
            $out/share/postgresql/extension/$ext.control > $out/share/postgresql/extension/$ext--$MIN_MAJ_VERSION.control
          rm $out/share/postgresql/extension/$ext.control
          ln -s $out/share/postgresql/extension/$ext--${version}.sql $out/share/postgresql/extension/$ext--$MIN_MAJ_VERSION.sql
        done

        # Add function definition and usage to tiger geocoder files
        for file in $out/share/postgresql/extension/postgis_tiger_geocoder*--${version}.sql; do
            sed -i "/SELECT postgis_extension_AddToSearchPath('tiger');/a SELECT postgis_extension_AddToSearchPath('extensions');" "$file"
        done
        # Original topology patching
        for file in $out/share/postgresql/extension/postgis_topology*--${version}.sql; do
          sed -i "/SELECT topology.AddToSearchPath('topology');/i SELECT topology.AddToSearchPath('extensions');" "$file"
        done

        # For the latest version, create default control file and symlink and copy SQL upgrade scripts
        if [[ "${version}" == "${latestVersion}" ]]; then
          for ext in ${lib.concatStringsSep " " (cExtensions ++ sqlExtensions)}; do
            {
              echo "default_version = '$MIN_MAJ_VERSION'"
              cat $out/share/postgresql/extension/$ext--$MIN_MAJ_VERSION.control
            } > $out/share/postgresql/extension/$ext.control
          done
          for prog in $out/bin/*; do # */
            ln -s $prog $prog-$MIN_MAJ_VERSION
          done
        else
          # remove migration scripts for non-latest version
          find $out/share/postgresql/extension -regex '.*--.*--.*\.sql' -delete

          for prog in $out/bin/*; do # */
            mv $prog $prog-$MIN_MAJ_VERSION
          done
        fi

        mkdir -p $doc/share/doc/postgis
        mv doc/* $doc/share/doc/postgis/
      '';

      passthru.tests.postgis = nixosTests.postgis;

      meta = with lib; {
        description = "Geographic Objects for PostgreSQL";
        homepage = "https://postgis.net/";
        changelog = "https://git.osgeo.org/gitea/postgis/postgis/raw/tag/${version}/NEWS";
        license = licenses.gpl2;
        inherit (postgresql.meta) platforms;
      };
    };
in
buildEnv {
  name = pname;
  paths = packages;

  pathsToLink = [
    "/lib"
    "/share/postgresql/extension"
  ];
  postBuild = ''
    # Verify all expected library files are present
    expectedFiles=${toString (numberOfVersions * builtins.length cExtensions)}
    actualFiles=$(ls -A $out/lib/*${postgresql.dlSuffix} | wc -l)

    if [[ "$actualFiles" != "$expectedFiles" ]]; then
      echo "Error: Expected $expectedFiles library files, found $actualFiles"
      echo "Files found:"
      ls -la $out/lib/${pname}*${postgresql.dlSuffix} || true
      exit 1
    fi
  '';

  passthru = {
    inherit versions numberOfVersions;
    pname = "${pname}-all";
    version =
      "multi-" + lib.concatStringsSep "-" (map (v: lib.replaceStrings [ "." ] [ "-" ] v) versions);
  };
}
