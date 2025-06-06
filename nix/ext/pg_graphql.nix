{
  lib,
  stdenv,
  buildEnv,
  fetchFromGitHub,
  postgresql,
  buildPgrxExtension_0_11_2,
  buildPgrxExtension_0_11_3,
  buildPgrxExtension_0_12_6,
  buildPgrxExtension_0_12_9,
  rust-bin,
  rsync,
}:

let
  pname = "pg_graphql";
  build =
    version: hash: rustVersion: buildPgrxExtension:
    let
      cargo = rust-bin.stable.${rustVersion}.default;
      previousVersions = lib.filter (v: v != version) versions;
    in
    buildPgrxExtension rec {
      inherit pname version postgresql;

      src = fetchFromGitHub {
        owner = "supabase";
        repo = pname;
        rev = "v${version}";
        inherit hash;
      };

      nativeBuildInputs = [ cargo ];
      buildInputs = [ postgresql ];

      CARGO = "${cargo}/bin/cargo";

      cargoLock = {
        lockFile = "${src}/Cargo.lock";
      };
      # Setting RUSTFLAGS in env to ensure it's available for all phases
      env = lib.optionalAttrs stdenv.isDarwin {
        POSTGRES_LIB = "${postgresql}/lib";
        PGPORT = toString (
          5430
          + (if builtins.match ".*_.*" postgresql.version != null then 1 else 0)
          # +1 for OrioleDB
          + ((builtins.fromJSON (builtins.substring 0 2 postgresql.version)) - 15) * 2
        ); # +2 for each major version
        RUSTFLAGS = "-C link-arg=-undefined -C link-arg=dynamic_lookup";
        NIX_BUILD_CORES = "4"; # Limit parallel jobs
        CARGO_BUILD_JOBS = "4"; # Limit cargo parallelism
      };
      CARGO_PROFILE_RELEASE_BUILD_OVERRIDE_DEBUG = true;

      preBuild = ''
        echo "Processing git tags..."
        echo '${builtins.concatStringsSep "," previousVersions}' | sed 's/,/\n/g' > git_tags.txt
      '';

      postInstall = ''
        mv $out/lib/${pname}${postgresql.dlSuffix} $out/lib/${pname}-${version}${postgresql.dlSuffix}

        create_sql_files() {
          echo "Creating SQL files for previous versions..."
          current_version="${version}"
          sql_file="$out/share/postgresql/extension/${pname}--$current_version.sql"

          if [ -f "$sql_file" ]; then
            while read -r previous_version; do
              if [ "$(printf '%s\n' "$previous_version" "$current_version" | sort -V | head -n1)" = "$previous_version" ] && [ "$previous_version" != "$current_version" ]; then
                new_file="$out/share/postgresql/extension/${pname}--$previous_version--$current_version.sql"
                sed -i 's/create\s\+function/CREATE OR REPLACE FUNCTION/Ig' "$sql_file"
                echo "Creating $new_file"
                {
                  echo "DROP EVENT TRIGGER IF EXISTS graphql_watch_ddl;"
                  echo "DROP EVENT TRIGGER IF EXISTS graphql_watch_drop;"
                  cat $sql_file
                } > "$new_file"
              fi
            done < git_tags.txt
          else
            echo "Warning: $sql_file not found"
          fi
          rm git_tags.txt
        }

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

        create_sql_files
        create_control_files
      '';

      preCheck = ''
        export PGRX_HOME=$(mktemp -d)
        export NIX_PGLIBDIR=$PGRX_HOME/${lib.versions.major postgresql.version}/lib
        ${lib.getExe rsync} --chmod=ugo+w -a ${postgresql}/ ${postgresql.lib}/ $PGRX_HOME/${lib.versions.major postgresql.version}/
        cargo pgrx init --pg${lib.versions.major postgresql.version} $PGRX_HOME/${lib.versions.major postgresql.version}/bin/pg_config
      '';

      meta = with lib; {
        description = "GraphQL support for PostreSQL";
        homepage = "https://github.com/supabase/${pname}";
        license = licenses.postgresql;
        inherit (postgresql.meta) platforms;
      };
    };
  allVersions = (builtins.fromJSON (builtins.readFile ./versions.json)).pg_graphql;
  supportedVersions = lib.filterAttrs (
    _: value: builtins.elem (lib.versions.major postgresql.version) value.postgresql
  ) allVersions;
  versions = lib.naturalSort (lib.attrNames supportedVersions);
  latestVersion = lib.last versions;
  numberOfVersions = builtins.length versions;
  mapPgrxExtension =
    version:
    {
      "0.11.2" = buildPgrxExtension_0_11_2;
      "0.11.3" = buildPgrxExtension_0_11_3;
      "0.12.6" = buildPgrxExtension_0_12_6;
      "0.12.9" = buildPgrxExtension_0_12_9;
    }
    ."${version}";
  packages = builtins.attrValues (
    lib.mapAttrs (
      name: value: build name value.hash value.rust (mapPgrxExtension value.pgrx)
    ) supportedVersions
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
