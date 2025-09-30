{
  pkgs,
  lib,
  stdenv,
  fetchFromGitHub,
  curl,
  postgresql,
  libuv,
  makeWrapper,
  switch-ext-version,
}:

let
  pname = "pg_net";
  build =
    version: hash:
    stdenv.mkDerivation rec {
      inherit pname version;

      buildInputs = [
        curl
        postgresql
      ] ++ lib.optional (version == "0.6") libuv;

      src = fetchFromGitHub {
        owner = "supabase";
        repo = pname;
        rev = "refs/tags/v${version}";
        inherit hash;
      };

      buildPhase = ''
        make PG_CONFIG=${postgresql}/bin/pg_config
      '';

      postPatch =
        lib.optionalString (version == "0.6") ''
          # handle collision with pg_net 0.10.0
          rm sql/pg_net--0.2--0.3.sql
          rm sql/pg_net--0.4--0.5.sql
          rm sql/pg_net--0.5.1--0.6.sql
        ''
        + lib.optionalString (version == "0.7.1") ''
          # handle collision with pg_net 0.10.0
          rm sql/pg_net--0.5.1--0.6.sql
        '';

      env.NIX_CFLAGS_COMPILE = lib.optionalString (lib.versionOlder version "0.19.1") "-Wno-error";

      installPhase = ''
        mkdir -p $out/{lib,share/postgresql/extension}

        # Install versioned library
        install -Dm755 ${pname}${postgresql.dlSuffix} $out/lib/${pname}-${version}${postgresql.dlSuffix}

        if [ -f sql/${pname}.sql ]; then
          cp sql/${pname}.sql $out/share/postgresql/extension/${pname}--${version}.sql
        else
          cp sql/${pname}--${version}.sql $out/share/postgresql/extension/${pname}--${version}.sql
        fi

        # Install upgrade scripts
        find . -name '${pname}--*--*.sql' -exec install -Dm644 {} $out/share/postgresql/extension/ \;

        # Create versioned control file with modified module path
        sed -e "/^default_version =/d" \
            -e "s|^module_pathname = .*|module_pathname = '\$libdir/${pname}'|" \
          ${pname}.control > $out/share/postgresql/extension/${pname}--${version}.control
      '';

      meta = with lib; {
        description = "Async networking for Postgres";
        homepage = "https://github.com/supabase/pg_net";
        platforms = postgresql.meta.platforms;
        license = licenses.postgresql;
      };
    };
  allVersions = (builtins.fromJSON (builtins.readFile ./versions.json)).pg_net;
  # Filter out versions that don't work on current platform
  platformFilteredVersions = lib.filterAttrs (
    name: _:
    # Exclude 0.11.0 on macOS due to epoll.h dependency
    !(stdenv.isDarwin && name == "0.11.0")
  ) allVersions;
  supportedVersions = lib.filterAttrs (
    _: value: builtins.elem (lib.versions.major postgresql.version) value.postgresql
  ) platformFilteredVersions;
  versions = lib.naturalSort (lib.attrNames supportedVersions);
  latestVersion = lib.last versions;
  numberOfVersions = builtins.length versions;
  packages = builtins.attrValues (
    lib.mapAttrs (name: value: build name value.hash) supportedVersions
  );
in
pkgs.buildEnv {
  name = pname;
  paths = packages;
  nativeBuildInputs = [ makeWrapper ];
  postBuild = ''
    {
      echo "default_version = '${latestVersion}'"
      cat $out/share/postgresql/extension/${pname}--${latestVersion}.control
    } > $out/share/postgresql/extension/${pname}.control
    ln -sfn ${pname}-${latestVersion}${postgresql.dlSuffix} $out/lib/${pname}${postgresql.dlSuffix}


    # checks
    (set -x
       test "$(ls -A $out/lib/${pname}*${postgresql.dlSuffix} | wc -l)" = "${
         toString (numberOfVersions + 1)
       }"
    )

    makeWrapper ${lib.getExe switch-ext-version} $out/bin/switch_pg_net_version \
      --prefix EXT_WRAPPER : "$out" --prefix EXT_NAME : "${pname}"
  '';

  passthru = {
    inherit versions numberOfVersions;
    pname = "${pname}-all";
    hasBackgroundWorker = true;
    defaultSettings = {
      shared_preload_libraries = [ "pg_net" ];
    };
    version =
      "multi-" + lib.concatStringsSep "-" (map (v: lib.replaceStrings [ "." ] [ "-" ] v) versions);
  };
}
