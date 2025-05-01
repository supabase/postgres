{
  lib,
  stdenv,
  fetchFromGitHub,
  postgresql,
  runCommand,
}:

let
  pname = "pgvector";

  meta = {
    description = "Open-source vector similarity search for Postgres";
    homepage = "https://github.com/${pname}/${pname}";
    maintainers = with lib.maintainers; [ olirice ];
    inherit (postgresql.meta) platforms;
    license = lib.licenses.postgresql;
  };

  versions = {
    "0.8.0" = "sha256-JsZV+I4eRMypXTjGmjCtMBXDVpqTIPHQa28ogXncE/Q=";
    "0.7.4" = "sha256-qwPaguQUdDHV8q6GDneLq5MuhVroPizpbqt7f08gKJI=";
  };

  mkPackage =
    version: hash:
    stdenv.mkDerivation (finalAttrs: {
      inherit pname version meta;

      src = fetchFromGitHub {
        owner = pname;
        repo = pname;
        rev = "refs/tags/v${finalAttrs.version}";
        inherit hash;
      };

      buildInputs = [ postgresql ];

      postBuild = ''
        cp sql/vector.sql vector--$version.sql

        sed -e "/^default_version =/d" \
          -e "s|^module_pathname = .*|module_pathname = '\$libdir/vector'|" \
          vector.control > vector--$version.control
      '';

      installPhase = ''
        mkdir -p $out/{lib,share/postgresql/extension}

        install -Dm755 vector${postgresql.dlSuffix} $out/lib/vector-$version${postgresql.dlSuffix}
        install -Dm644 vector--$version.sql $out/share/postgresql/extension/
        install -Dm644 vector--$version.control $out/share/postgresql/extension/
      '';
    });

  packages = lib.listToAttrs (
    lib.attrValues (
      lib.mapAttrs (version: hash: lib.nameValuePair "v${version}" (mkPackage version hash)) versions
    )
  );
in
runCommand "${pname}-all"
  {
    inherit pname meta;
    version =
      "multi-"
      + lib.concatStringsSep "-" (map (v: lib.replaceStrings [ "." ] [ "-" ] v) (lib.attrNames versions));

    buildInputs = lib.attrValues packages;

    passthru = {
      inherit packages;
    };
  }
  ''
    mkdir -p $out/{lib,share/postgresql/extension,bin}

    # Install all versions
    for drv in ''${buildInputs[@]}; do
      ln -sv $drv/lib/* $out/lib/
      cp -v --no-clobber $drv/share/postgresql/extension/* $out/share/postgresql/extension/ || true
    done

    # Create default symlinks
    latest_control=$(ls -v $out/share/postgresql/extension/vector--*.control | tail -n1)
    latest_version=$(basename "$latest_control" | sed -E 's/vector--([0-9.]+).control/\1/')
      
    # Create main control file with default_version
    echo "default_version = '$latest_version'" > $out/share/postgresql/extension/vector.control
    cat "$latest_control" >> $out/share/postgresql/extension/vector.control
      
    # Library symlink
    ln -sfnv vector-$latest_version${postgresql.dlSuffix} $out/lib/vector${postgresql.dlSuffix}
  ''
