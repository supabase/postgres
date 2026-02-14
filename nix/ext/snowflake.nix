{
  lib,
  stdenv,
  buildEnv,
  fetchFromGitHub,
  postgresql,
}:

let
  pname = "snowflake";
  allVersions = (builtins.fromJSON (builtins.readFile ./versions.json)).${pname};
  supportedVersions = lib.filterAttrs (
    _: value: builtins.elem (lib.versions.major postgresql.version) value.postgresql
  ) allVersions;
  versions = lib.naturalSort (lib.attrNames supportedVersions);
  latestVersion = lib.last versions;
  numberOfVersions = builtins.length versions;
  build =
    version: hash:
    stdenv.mkDerivation rec {
      inherit pname version;

      buildInputs = [ postgresql ];

      src = fetchFromGitHub {
        owner = "pgEdge";
        repo = pname;
        rev = "v${version}";
        inherit hash;
      };

      makeFlags = [ "USE_PGXS=1" ];

      installPhase = ''
        mkdir -p $out/{lib,share/postgresql/extension}

        install -Dm755 ${pname}${postgresql.dlSuffix} $out/lib/${pname}-${version}${postgresql.dlSuffix}

        # Copy all SQL files (base install + migration scripts)
        cp *.sql $out/share/postgresql/extension/

        # Control file with versioned module_pathname
        sed -e "/^default_version =/d" \
            -e "s|^module_pathname = .*|module_pathname = '\$libdir/${pname}'|" \
          ${pname}.control > $out/share/postgresql/extension/${pname}--${version}.control
      '';

      meta = with lib; {
        description = "Snowflake-style unique ID generator for PostgreSQL";
        homepage = "https://github.com/pgEdge/snowflake";
        license = licenses.postgresql;
        inherit (postgresql.meta) platforms;
      };
    };
  packages = builtins.attrValues (
    lib.mapAttrs (name: value: build name value.hash) supportedVersions
  );
in
buildEnv {
  name = pname;
  paths = packages;
  pathsToLink = [
    "/lib"
    "/share/postgresql/extension"
  ];
  postBuild = ''
    ln -sfn ${pname}-${latestVersion}${postgresql.dlSuffix} $out/lib/${pname}${postgresql.dlSuffix}

    {
      echo "default_version = '${latestVersion}'"
      cat $out/share/postgresql/extension/${pname}--${latestVersion}.control
    } > $out/share/postgresql/extension/${pname}.control
  '';

  passthru = {
    inherit versions numberOfVersions pname;
    version =
      "multi-" + lib.concatStringsSep "-" (map (v: lib.replaceStrings [ "." ] [ "-" ] v) versions);
  };
}
