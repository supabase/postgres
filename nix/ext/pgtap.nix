{
  lib,
  stdenv,
  fetchFromGitHub,
  postgresql,
  perl,
  perlPackages,
  which,
  runCommand,
}:
let
  pname = "pgtap";

  meta = {
    description = "A unit testing framework for PostgreSQL";
    longDescription = ''
      pgTAP is a unit testing framework for PostgreSQL written in PL/pgSQL and PL/SQL.
      It includes a comprehensive collection of TAP-emitting assertion functions,
      as well as the ability to integrate with other TAP-emitting test frameworks.
      It can also be used in the xUnit testing style.
    '';
    homepage = "https://pgtap.org";
    inherit (postgresql.meta) platforms;
    license = lib.licenses.mit;
  };

  versions = {
    "1.3.3" = "sha256-YgvfLGF7pLVcCKD66NnWAydDxtoYHH1DpLiYTEKHJ0E=";
    "1.3.2" = "sha256-jPfYp94mZenKctCW+3tyyvdgVKW6TDsG1/dbBlHK3vE=";
    "1.3.1" = "sha256-HOgCb1CCfsfbMbMMWuzFJ4B8CfVm9b0sI2zBY3/kqyI=";
    "1.3.0" = "sha256-RaafUnrMRbvyf2m2Z+tK6XxVXDGnaOkYkSMxIJLnf6A=";
    "1.2.0" = "sha256-lb0PRffwo6J5a6Hqw1ggvn0cW7gPZ02OEcLPi9ineI8=";
  };

  mkPackage =
    version: hash:
    stdenv.mkDerivation (finalAttrs: {
      inherit pname version meta;

      src = fetchFromGitHub {
        owner = "theory";
        repo = "pgtap";
        rev = "refs/tags/v${version}";
        inherit hash;
      };

      nativeBuildInputs = [
        postgresql
        perl
        perlPackages.TAPParserSourceHandlerpgTAP
        which
      ];

      postBuild = ''
        sed -e "/^default_version =/d" \
          -e "s|^module_pathname = .*|module_pathname = '\$libdir/pgtap'|" \
          pgtap.control > pgtap--$version.control
      '';

      installPhase = ''
        mkdir -p $out/share/postgresql/extension

        install -Dm644 sql/pgtap--$version.sql $out/share/postgresql/extension
        install -Dm644 pgtap--$version.control $out/share/postgresql/extension
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
    version = "multi-" + lib.concatStringsSep "-" (map (v: lib.replaceStrings ["."] ["-"] v) (lib.attrNames versions));

    buildInputs = lib.attrValues packages;

    passthru = {
      inherit packages;
    };
  }
  ''
    mkdir -p $out/{lib,share/postgresql/extension,bin}

    # Install all versions
    for drv in ''${buildInputs[@]}; do
      ls $drv/share/postgresql/extension/
      cp -v --no-clobber $drv/share/postgresql/extension/* $out/share/postgresql/extension/ || true
    done

    # Create default symlinks
    latest_control=$(ls -v $out/share/postgresql/extension/pgtap--*.control | tail -n1)
    latest_version=$(basename "$latest_control" | sed -E 's/pgtap--([0-9.]+).control/\1/')
        
    # Create main control file with default_version
    echo "default_version = '$latest_version'" > $out/share/postgresql/extension/pgtap.control
    cat "$latest_control" >> $out/share/postgresql/extension/pgtap.control
  ''
