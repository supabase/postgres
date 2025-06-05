{ lib, pkgs, stdenv, fetchFromGitHub, postgresql, buildPgrxExtension_0_10_2
, buildPgrxExtension_0_12_6, buildPgrxExtension_0_11_3, rust-bin }:
let
  pname = "pg_jsonschema";
  build = version: hash: rustVersion: buildPgrxExtension:
    let
      cargo = rust-bin.stable.${rustVersion}.default;
      src = fetchFromGitHub {
        owner = "supabase";
        repo = pname;
        rev = "v${version}";
        inherit hash;
      };
      lockFile = if builtins.pathExists "${src}/Cargo.lock" then
        "${src}/Cargo.lock"
      else
        ./Cargo-${version}.lock;
    in buildPgrxExtension rec {
      inherit pname version postgresql src;

      postPatch = if builtins.pathExists ./Cargo-${version}.lock then ''
        ln -s ${./Cargo-${version}.lock} Cargo.lock
      '' else
        "";

      nativeBuildInputs = [ cargo ];
      buildInputs = [ postgresql ];
      # update the following array when the pg_jsonschema version is updated
      # required to ensure that extensions update scripts from previous versions are generated

      previousVersions =
        [ "0.3.1" "0.3.0" "0.2.0" "0.1.4" "0.1.3" "0.1.2" "0.1.1" "0.1.0" ];
      CARGO = "${cargo}/bin/cargo";
      #darwin env needs PGPORT to be unique for build to not clash with other pgrx extensions
      env = lib.optionalAttrs stdenv.isDarwin {
        POSTGRES_LIB = "${postgresql}/lib";
        RUSTFLAGS = "-C link-arg=-undefined -C link-arg=dynamic_lookup";
        PGPORT = toString (5441
          + (if builtins.match ".*_.*" postgresql.version != null then 1 else 0)
          + # +1 for OrioleDB
          ((builtins.fromJSON (builtins.substring 0 2 postgresql.version)) - 15)
          * 2); # +2 for each major version
      };

      cargoLock = {
        inherit lockFile;
        allowBuiltinFetchGit = false;
      };

      preCheck = ''
        export PGRX_HOME=$(mktemp -d)
        export NIX_PGLIBDIR=$PGRX_HOME/${
          lib.versions.major postgresql.version
        }/lib
        ${
          lib.getExe pkgs.rsync
        } --chmod=ugo+w -a ${postgresql}/ ${postgresql.lib}/ $PGRX_HOME/${
          lib.versions.major postgresql.version
        }/
        cargo pgrx init --pg${
          lib.versions.major postgresql.version
        } $PGRX_HOME/${lib.versions.major postgresql.version}/bin/pg_config
      '';

      doCheck = true;

      preBuild = ''
        echo "Processing git tags..."
        echo '${
          builtins.concatStringsSep "," previousVersions
        }' | sed 's/,/\n/g' > git_tags.txt
      '';

      postInstall = ''
        mv $out/lib/${pname}${postgresql.dlSuffix} $out/lib/${pname}-${version}${postgresql.dlSuffix}

        create_sql_files() {
          echo "Creating SQL files for previous versions..."
          current_version="${version}"
          sql_file="$out/share/postgresql/extension/pg_jsonschema--$current_version.sql"

          if [ -f "$sql_file" ]; then
            while read -r previous_version; do
              if [ "$(printf '%s\n' "$previous_version" "$current_version" | sort -V | head -n1)" = "$previous_version" ] && [ "$previous_version" != "$current_version" ]; then
                new_file="$out/share/postgresql/extension/pg_jsonschema--$previous_version--$current_version.sql"
                echo "Creating $new_file"
                cp "$sql_file" "$new_file"
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

      meta = with lib; {
        description = "JSON Schema Validation for PostgreSQL";
        homepage = "https://github.com/supabase/${pname}";
        platforms = postgresql.meta.platforms;
        license = licenses.postgresql;
      };
    };
  allVersions =
    (builtins.fromJSON (builtins.readFile ../versions.json)).pg_jsonschema;
  supportedVersions = lib.filterAttrs (_: value:
    builtins.elem (lib.versions.major postgresql.version) value.postgresql)
    allVersions;
  versions = lib.naturalSort (lib.attrNames supportedVersions);
  latestVersion = lib.last versions;
  numberOfVersions = builtins.length versions;
  mapPgrxExtension = version:
    {
      "0.10.2" = buildPgrxExtension_0_10_2;
      "0.11.3" = buildPgrxExtension_0_11_3;
      "0.12.6" = buildPgrxExtension_0_12_6;
    }."${version}";
  packages = builtins.attrValues (lib.mapAttrs (name: value:
    build name value.hash value.rust (mapPgrxExtension value.pgrx))
    supportedVersions);
in pkgs.buildEnv {
  name = pname;
  paths = packages;
  pathsToLink = [ "/lib" "/share/postgresql/extension" ];
  passthru = {
    inherit versions numberOfVersions;
    pname = "${pname}-all";
    version = "multi-" + lib.concatStringsSep "-"
      (map (v: lib.replaceStrings [ "." ] [ "-" ] v) versions);
  };
}
