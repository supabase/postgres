{
  callPackages,
  lib,
  stdenv,
  buildEnv,
  fetchFromGitHub,
  postgresql,
  rust-bin,
  rsync,
  system,
  rustPlatform,
}:

let
  pname = "pg_graphql";
  build =
    version: hash: rustVersion: pgrxVersion:
    let
      cargo = rust-bin.stable.${rustVersion}.default;
      mkPgrxExtension = callPackages ../../cargo-pgrx/mkPgrxExtension.nix {
        inherit rustVersion pgrxVersion;
      };
      src = fetchFromGitHub {
        owner = "supabase";
        repo = pname;
        rev = "v${version}";
        inherit hash;
      };
      lockFile =
        if builtins.pathExists "${src}/Cargo.lock" then "${src}/Cargo.lock" else ./Cargo-${version}.lock;
    in
    mkPgrxExtension (
      rec {
        inherit
          pname
          version
          postgresql
          src
          ;

        nativeBuildInputs = [ cargo ];
        buildInputs = [ postgresql ];

        CARGO = "${cargo}/bin/cargo";

        cargoLock = {
          inherit lockFile;
        };
        # Setting RUSTFLAGS in env to ensure it's available for all phases
        env = lib.optionalAttrs stdenv.isDarwin {
          POSTGRES_LIB = "${postgresql}/lib";
          RUSTFLAGS = "-C link-arg=-undefined -C link-arg=dynamic_lookup";
          NIX_BUILD_CORES = "4";
          CARGO_BUILD_JOBS = "4";
        };

        CARGO_PROFILE_RELEASE_BUILD_OVERRIDE_DEBUG = true;

        postInstall = ''
          mv $out/lib/${pname}${postgresql.dlSuffix} $out/lib/${pname}-${version}${postgresql.dlSuffix}

          create_control_files() {
            sed -e "/^default_version =/d" \
                -e "s|^module_pathname = .*|module_pathname = '\$libdir/${pname}'|" \
              ${pname}.control > $out/share/postgresql/extension/${pname}--${version}.control
            rm $out/share/postgresql/extension/${pname}.control

            if [[ "${version}" == "${latestVersion}" ]]; then
              {
                echo "default_version = '${latestVersion}'"
                cat $out/share/postgresql/extension/${pname}--${latestVersion}.control
              } > $out/share/postgresql/extension/${pname}.control
              ln -sfn ${pname}-${latestVersion}${postgresql.dlSuffix} $out/lib/${pname}${postgresql.dlSuffix}
            fi
          }

          create_control_files
        '';

        pgrxBinaryName = if builtins.compareVersions "0.7.4" pgrxVersion >= 0 then "pgx" else "pgrx";

        preCheck = ''
          export PGRX_HOME="$(mktemp -d)"
          export PG_VERSION="${lib.versions.major postgresql.version}"
          export NIX_PGLIBDIR="$PGRX_HOME/$PG_VERSION/lib"
          export PATH="$PGRX_HOME/$PG_VERSION/bin:$PATH"
          ${lib.getExe rsync} --chmod=ugo+w -a ${postgresql}/ ${postgresql.lib}/ "$PGRX_HOME/$PG_VERSION/"
          cargo ${pgrxBinaryName} init "--pg$PG_VERSION" "$PGRX_HOME/$PG_VERSION/bin/pg_config"
          cargo ${pgrxBinaryName} install --release --features "pg$PG_VERSION"
        '';

        doCheck = true;

        checkPhase = ''
          runHook preCheck
          bash -x ./bin/installcheck
          runHook postCheck
        '';

        meta = with lib; {
          description = "GraphQL support for PostreSQL";
          homepage = "https://github.com/supabase/${pname}";
          license = licenses.postgresql;
          inherit (postgresql.meta) platforms;
        };
      }
      //
        lib.optionalAttrs
          (
            # Fix bindgen error on aarch64-linux for versions using pgrx with bindgen 0.68.1
            # This affects pgrx 0.6.1 through 0.11.2 which have issues with ARM NEON vector ABI
            # We apply the fix to all versions up to 1.5.1 (last version before 1.5.4 which uses 0.11.2)
            builtins.compareVersions "1.5.4" version > 0
          )
          {
            # Fix bindgen error on aarch64-linux by using an older version of clang
            bindgenHook =
              let
                nixos2211 = (
                  import (builtins.fetchTarball {
                    url = "https://channels.nixos.org/nixos-22.11/nixexprs.tar.xz";
                    sha256 = "1j7h75a9hwkkm97jicky5rhvzkdwxsv5v46473rl6agvq2sj97y1";
                  }) { inherit system; }
                );
              in
              rustPlatform.bindgenHook.overrideAttrs {
                libclang = nixos2211.clang.cc.lib;
                clang = nixos2211.clang;
              };
          }
      // lib.optionalAttrs (builtins.compareVersions "1.2.0" version >= 0) {
        # Add missing Cargo.lock
        patches = [ ./0001-Add-missing-Cargo.lock-${version}.patch ];

        cargoLock = {
          lockFile = ./Cargo-${version}.lock;
          outputHashes = {
            "pgx-contrib-spiext-0.1.0" =
              if (version == "1.2.0") then
                "sha256-sUokKg8Jaf2/faXlHg1ui2pyJ05jdGxxgeJzhPOds9M="
              else
                "sha256-1hAA8DnCYkKDRdIDXrJzo59+sCz4i+oI9CPN+Ti6jWA=";
          };
        };
      }
    );
  allVersions = (builtins.fromJSON (builtins.readFile ../versions.json)).pg_graphql;
  supportedVersions = lib.filterAttrs (
    _: value: builtins.elem (lib.versions.major postgresql.version) value.postgresql
  ) allVersions;
  versions = lib.naturalSort (lib.attrNames supportedVersions);
  latestVersion = lib.last versions;
  numberOfVersions = builtins.length versions;
  packages = builtins.attrValues (
    lib.mapAttrs (name: value: build name value.hash value.rust value.pgrx) supportedVersions
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
    create_sql_files() {
      PREVIOUS_VERSION=""
      while IFS= read -r i; do
        FILENAME=$(basename "$i")
        DIRNAME=$(dirname "$i")
        VERSION="$(grep -oE '[0-9]+\.[0-9]+\.[0-9]+' <<< $FILENAME)"
        if [[ "$PREVIOUS_VERSION" != "" ]]; then
          echo "Processing $i"
          sed -i 's/CREATE[[:space:]]*FUNCTION/CREATE OR REPLACE FUNCTION/Ig' "$i"
          {
            echo "DROP EVENT TRIGGER IF EXISTS graphql_watch_ddl CASCADE;"
            echo "DROP EVENT TRIGGER IF EXISTS graphql_watch_drop CASCADE;"
            cat "$i"
          } > "$i.tmp" && mv "$i.tmp" "$i"
          MIGRATION_FILENAME="$DIRNAME/''${FILENAME/$VERSION/$PREVIOUS_VERSION--$VERSION}"
          cp "$i" "$MIGRATION_FILENAME"
        fi
        PREVIOUS_VERSION="$VERSION"
      done < <(find $out -name '*.sql' | sort -V)
      # handle special case of mergeless upgrade from 1.5.1-mergeless to 1.5.4
      if [[ -f $out/share/postgresql/extension/pg_graphql--1.5.1--1.5.4.sql ]]; then
        cp $out/share/postgresql/extension/pg_graphql--1.5.1--1.5.4.sql $out/share/postgresql/extension/pg_graphql--1.5.1-mergeless--1.5.4.sql
      fi
    }

    create_sql_files

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
    version =
      "multi-" + lib.concatStringsSep "-" (map (v: lib.replaceStrings [ "." ] [ "-" ] v) versions);
  };
}
