{
  lib,
  pkgs,
  stdenv,
  callPackages,
  fetchFromGitHub,
  postgresql,
  rust-bin,
  darwin,
}:
let
  pname = "pg_jsonschema";
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
    mkPgrxExtension rec {
      inherit
        pname
        version
        postgresql
        src
        ;

      postPatch =
        if builtins.pathExists ./Cargo-${version}.lock then
          ''
            ln -s ${./Cargo-${version}.lock} Cargo.lock
          ''
        else
          "";

      nativeBuildInputs = [ cargo ];
      buildInputs = [
        postgresql
      ] ++ lib.optionals stdenv.isDarwin [ darwin.apple_sdk.frameworks.SystemConfiguration ];
      # update the following array when the pg_jsonschema version is updated
      # required to ensure that extensions update scripts from previous versions are generated

      previousVersions = [
        "0.3.1"
        "0.3.0"
        "0.2.0"
        "0.1.4"
        "0.1.3"
        "0.1.2"
        "0.1.1"
        "0.1.0"
      ];
      CARGO = "${cargo}/bin/cargo";
      #darwin env needs PGPORT to be unique for build to not clash with other pgrx extensions
      env = lib.optionalAttrs stdenv.isDarwin {
        POSTGRES_LIB = "${postgresql}/lib";
        RUSTFLAGS = "-C link-arg=-undefined -C link-arg=dynamic_lookup";
        PGPORT = toString (
          5441
          + (if builtins.match ".*_.*" postgresql.version != null then 1 else 0)
          # +1 for OrioleDB
          + ((builtins.fromJSON (builtins.substring 0 2 postgresql.version)) - 15) * 2
        ); # +2 for each major version
      };

      cargoLock = {
        inherit lockFile;
        allowBuiltinFetchGit = false;
      };

      preCheck = ''
        export PGRX_HOME=$(mktemp -d)
        export NIX_PGLIBDIR=$PGRX_HOME/${lib.versions.major postgresql.version}/lib
        ${lib.getExe pkgs.rsync} --chmod=ugo+w -a ${postgresql}/ ${postgresql.lib}/ $PGRX_HOME/${lib.versions.major postgresql.version}/
        cargo pgrx init --pg${lib.versions.major postgresql.version} $PGRX_HOME/${lib.versions.major postgresql.version}/bin/pg_config
      '';

      doCheck = true;

      preBuild = ''
        echo "Processing git tags..."
        echo '${builtins.concatStringsSep "," previousVersions}' | sed 's/,/\n/g' > git_tags.txt
      '';

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

      meta = with lib; {
        description = "JSON Schema Validation for PostgreSQL";
        homepage = "https://github.com/supabase/${pname}";
        platforms = postgresql.meta.platforms;
        license = licenses.postgresql;
      };
    };
  allVersions = (builtins.fromJSON (builtins.readFile ../versions.json)).pg_jsonschema;
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
(pkgs.buildEnv {
  name = pname;
  paths = packages;
  pathsToLink = [
    "/lib"
    "/share/postgresql/extension"
  ];
  postBuild = ''
    # checks
    (set -x
       test "$(ls -A $out/lib/${pname}*${postgresql.dlSuffix} | wc -l)" = "${
         toString (numberOfVersions + 1)
       }"
    )

    create_sql_files() {
      PREVIOUS_VERSION=""
      while IFS= read -r i; do
        sed -i 's/CREATE  FUNCTION/CREATE OR REPLACE FUNCTION/g' "$i"
        FILENAME=$(basename "$i")
        DIRNAME=$(dirname "$i")
        VERSION="$(grep -oE '[0-9]+\.[0-9]+\.[0-9]+' <<< $FILENAME)"
        if [[ "$PREVIOUS_VERSION" != "" ]]; then
          echo "Processing $i"
          MIGRATION_FILENAME="$DIRNAME/''${FILENAME/$VERSION/$PREVIOUS_VERSION--$VERSION}"
          cp "$i" "$MIGRATION_FILENAME"
        fi
        PREVIOUS_VERSION="$VERSION"
      done < <(find $out -name '*.sql' | sort -V)
    }

    create_sql_files
  '';

  passthru = {
    inherit versions numberOfVersions pname;
    version =
      "multi-" + lib.concatStringsSep "-" (map (v: lib.replaceStrings [ "." ] [ "-" ] v) versions);
  };
}).overrideAttrs
  (_: {
    requiredSystemFeatures = [ "big-parallel" ];
  })
