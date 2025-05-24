{
  lib,
  stdenv,
  fetchFromGitHub,
  libsodium,
  postgresql,
  runCommand,
}:
let
  pname = "vault";

  meta = with lib; {
    description = "Store encrypted secrets in PostgreSQL";
    homepage = "https://github.com/supabase/${pname}";
    platforms = postgresql.meta.platforms;
    license = licenses.postgresql;
  };

  versions = {
    "0.3.1" = "sha256-MC87bqgtynnDhmNZAu96jvfCpsGDCPB0g5TZfRQHd30=";
  };

  mkPackage =
    version: hash:
    stdenv.mkDerivation (finalAttrs: {
      inherit pname version meta;

      src = fetchFromGitHub {
        owner = "supabase";
        repo = finalAttrs.pname;
        rev = "refs/tags/v${finalAttrs.version}";
        inherit hash;
      };

      buildInputs = [
        libsodium
        postgresql
      ];

      postBuild = ''
        sed -e "/^default_version =/d" \
          -e "s|^module_pathname = .*|module_pathname = '\$libdir/vault'|" \
          supabase_vault.control > supabase_vault--$version.control
      '';

      installPhase = ''
        mkdir -p $out/{lib,share/postgresql/extension}

        install -Dm755 supabase_vault${postgresql.dlSuffix} $out/lib/supabase_vault-$version${postgresql.dlSuffix}
        install -Dm644 supabase_vault--$version.control $out/share/postgresql/extension/
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
    latest_control=$(ls -v $out/share/postgresql/extension/supabase_vault--*.control | tail -n1)
    latest_version=$(basename "$latest_control" | sed -E 's/supabase_vault--([0-9.]+).control/\1/')

    # Create main control file with default_version
    echo "default_version = '$latest_version'" > $out/share/postgresql/extension/supabase_vault.control
    cat "$latest_control" >> $out/share/postgresql/extension/supabase_vault.control

    # Library symlink
    ln -sfnv supabase_vault-$latest_version${postgresql.dlSuffix} $out/lib/supabase_vault${postgresql.dlSuffix}
  ''
