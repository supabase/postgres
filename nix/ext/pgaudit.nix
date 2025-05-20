{ lib, stdenv, fetchFromGitHub, libkrb5, openssl, postgresql, runCommand }:
#adapted from https://github.com/NixOS/nixpkgs/blob/master/pkgs/servers/sql/postgresql/ext/pgaudit.nix
let
  pname = "pgaudit";

  meta = with lib; {
    description = "Open Source PostgreSQL Audit Logging";
    homepage = "https://github.com/pgaudit/pgaudit";
    changelog = "https://github.com/pgaudit/pgaudit/releases/tag/${source.version}";
    platforms = postgresql.meta.platforms;
    license = licenses.postgresql;
  };

  versions = {
    "17" = {
      "17.0" = "sha256-3ksq09wiudQPuBQI3dhEQi8IkXKLVIsPFgBnwLiicro=";
    };
    "16" = {
      "16.0" = "sha256-8+tGOl1U5y9Zgu+9O5UDDE4bec4B0JC/BQ6GLhHzQzc=";
    };
    "15" = {
      "1.7.0" = "sha256-8pShPr4HJaJQPjW1iPJIpj3CutTx8Tgr+rOqoXtgCcw=";
    };
  }.${lib.versions.major postgresql.version} or (throw "Source for pgaudit is not available for ${postgresql.version}");

  mkPackage =
    version: hash:
    stdenv.mkDerivation (finalAttrs: {
      inherit pname version meta;

      src = fetchFromGitHub {
        owner = "pgaudit";
        repo = "pgaudit";
        rev = version;
        inherit hash;
      };

      buildInputs = [ libkrb5 openssl postgresql ];

      makeFlags = [ "USE_PGXS=1" ];

      postBuild = ''
        sed -e "/^default_version =/d" \
          -e "s|^module_pathname = .*|module_pathname = '\$libdir/pgaudit'|" \
          pgaudit.control > pgaudit--$version.control
      '';

      installPhase = ''
        mkdir -p $out/{lib,share/postgresql/extension}

        install -Dm755 pgaudit${postgresql.dlSuffix} $out/lib/pgaudit-$version${postgresql.dlSuffix}
        install -Dm644 pgaudit--$version.sql $out/share/postgresql/extension/
        install -Dm644 pgaudit--$version.control $out/share/postgresql/extension/
      '';
    });

  packages = lib.listToAttrs (
    lib.attrValues (
      lib.mapAttrs (version: hash: lib.nameValuePair "v${version}" (mkPackage version hash)) versions
    )
  );
in
runCommand "${pname}-all" {
  inherit pname meta;
  version = "multi-" + lib.concatStringsSep "-" (map (v: lib.replaceStrings ["."] ["-"] v) (lib.attrNames versions));

  buildInputs = lib.attrValues packages;

  passthru = {
    inherit packages;
  };
} ''
  mkdir -p $out/{lib,share/postgresql/extension,bin}

  # Install all versions
  for drv in ''${buildInputs[@]}; do
    ln -sv $drv/lib/* $out/lib/
    cp -v --no-clobber $drv/share/postgresql/extension/* $out/share/postgresql/extension/ || true
  done

  # Create default symlinks
  latest_control=$(ls -v $out/share/postgresql/extension/pgaudit--*.control | tail -n1)
  latest_version=$(basename "$latest_control" | sed -E 's/pgaudit--([0-9.]+).control/\1/')
      
  # Create main control file with default_version
  echo "default_version = '$latest_version'" > $out/share/postgresql/extension/pgaudit.control
  cat "$latest_control" >> $out/share/postgresql/extension/pgaudit.control
      
  # Library symlink
  ln -sfnv pgaudit-$latest_version${postgresql.dlSuffix} $out/lib/pgaudit${postgresql.dlSuffix}
''
