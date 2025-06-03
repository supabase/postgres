{ pkgs, lib, stdenv, fetchFromGitHub, curl, postgresql, libuv }:

let
  pname = "pg_net";
  build = version: hash:
    stdenv.mkDerivation rec {
      inherit pname version;

      buildInputs = [ curl postgresql ]
        ++ lib.optional (version == "0.6") libuv;

      src = fetchFromGitHub {
        owner = "supabase";
        repo = pname;
        rev = "refs/tags/v${version}";
        inherit hash;
      };

      buildPhase = ''
        make PG_CONFIG=${postgresql}/bin/pg_config
      '';

      postPatch = lib.optionalString (version == "0.6") ''
        # handle collision with pg_net 0.10.0
        rm sql/pg_net--0.2--0.3.sql
        rm sql/pg_net--0.4--0.5.sql
        rm sql/pg_net--0.5.1--0.6.sql
      '' + lib.optionalString (version == "0.7.1") ''
        # handle collision with pg_net 0.10.0
        rm sql/pg_net--0.5.1--0.6.sql
      '';

      env.NIX_CFLAGS_COMPILE = "-Wno-error";

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
  supportedVersions = lib.filterAttrs (_: value:
    builtins.elem (lib.versions.major postgresql.version) value.postgresql)
    allVersions;
  versions = lib.naturalSort (lib.attrNames supportedVersions);
  latestVersion = lib.last versions;
  numberOfVersions = builtins.length versions;
  packages = builtins.attrValues
    (lib.mapAttrs (name: value: build name value.hash) supportedVersions);
in pkgs.buildEnv {
  name = pname;
  paths = packages;
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
  '';

  passthru = {
    inherit versions numberOfVersions;
    pname = "${pname}-all";
    version = "multi-" + lib.concatStringsSep "-"
      (map (v: lib.replaceStrings [ "." ] [ "-" ] v) versions);
  };
}
