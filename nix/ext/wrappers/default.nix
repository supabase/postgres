{
  lib,
  stdenv,
  callPackages,
  fetchFromGitHub,
  openssl,
  pkg-config,
  postgresql,
  buildEnv,
  darwin,
  rust-bin,
  git,
}:
let
  pname = "wrappers";
  build =
    version: hash: rustVersion: pgrxVersion:
    let
      cargo = rust-bin.stable.${rustVersion}.default;
      #previousVersions = lib.filter (v: v != version) versions; # FIXME
      mkPgrxExtension = callPackages ../../cargo-pgrx/mkPgrxExtension.nix {
        inherit rustVersion pgrxVersion;
      };
    in
    mkPgrxExtension rec {
      inherit pname version postgresql;

      src = fetchFromGitHub {
        owner = "supabase";
        repo = "wrappers";
        rev = "v${version}";
        inherit hash;
      };

      nativeBuildInputs = [
        pkg-config
        cargo
        git
      ];
      buildInputs =
        [
          openssl
          postgresql
        ]
        ++ lib.optionals stdenv.isDarwin [
          darwin.apple_sdk.frameworks.CoreFoundation
          darwin.apple_sdk.frameworks.Security
          darwin.apple_sdk.frameworks.SystemConfiguration
        ];

      NIX_LDFLAGS = "-L${postgresql}/lib -lpq";

      # Set necessary environment variables for pgrx in darwin only
      env = lib.optionalAttrs stdenv.isDarwin {
        POSTGRES_LIB = "${postgresql}/lib";
        RUSTFLAGS = "-C link-arg=-undefined -C link-arg=dynamic_lookup";
      };

      OPENSSL_NO_VENDOR = 1;
      #need to set this to 2 to avoid cpu starvation
      CARGO_BUILD_JOBS = "2";
      CARGO = "${cargo}/bin/cargo";

      cargoLock = {
        lockFile = "${src}/Cargo.lock";
        outputHashes =
          if builtins.compareVersions "0.4.2" version >= 0 then
            {
              "clickhouse-rs-1.0.0-alpha.1" = "sha256-0zmoUo/GLyCKDLkpBsnLAyGs1xz6cubJhn+eVqMEMaw=";
            }
          else if builtins.compareVersions "0.5.0" version >= 0 then
            {
              "clickhouse-rs-1.1.0-alpha.1" = "sha256-G+v4lNP5eK2U45D1fL90Dq24pUSlpIysNCxuZ17eac0=";
            }
          else
            {
              "clickhouse-rs-1.1.0-alpha.1" = "sha256-nKiGzdsAgJej8NgyVOqHaD1sZLrNF1RPfEhu2pRwZ6o=";
              "iceberg-0.5.0" = "sha256-dYPZdpP7kcp49UxsCZrZi3xMJ4rJiB8H65dMMR9Z1Yk=";
            };
      };

      preConfigure = ''
        cd wrappers

        # update the clickhouse-rs dependency
        # append the branch name to the git URL to help cargo locate the commit
        # while maintaining the rev for reproducibility
        awk -i inplace '
        /\[dependencies.clickhouse-rs\]/ {
          print
          getline
          if ($0 ~ /git =/) {
            print "git = \"https://github.com/suharev7/clickhouse-rs/async-await\""
          } else {
            print
          }
          while ($0 !~ /^\[/ && NF > 0) {
            getline
            if ($0 ~ /rev =/) print
            if ($0 ~ /^\[/) print
          }
          next
        }
        { print }
        ' Cargo.toml

        # Verify the file is still valid TOML, break build with this erroru
        # if it is not
        if ! cargo verify-project 2>/dev/null; then
          echo "Failed to maintain valid TOML syntax"
          exit 1
        fi

        cd ..
      '';

      buildAndTestSubdir = "wrappers";
      buildFeatures = [
        "helloworld_fdw"
        "all_fdws"
      ];
      doCheck = false;

      postInstall = ''
         create_control_files() {
           sed -e "/^default_version =/d" \
               -e "s|^module_pathname = .*|module_pathname = '\$libdir/${pname}'|" \
             $out/share/postgresql/extension/${pname}.control > $out/share/postgresql/extension/${pname}--${version}.control
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
        description = "Various Foreign Data Wrappers (FDWs) for PostreSQL";
        homepage = "https://github.com/supabase/wrappers";
        license = licenses.postgresql;
        inherit (postgresql.meta) platforms;
      };
    };
  allVersions = (builtins.fromJSON (builtins.readFile ../versions.json)).wrappers;
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
    # checks
    (set -x
       test "$(ls -A $out/lib/${pname}*${postgresql.dlSuffix} | wc -l)" = "${
         toString (numberOfVersions + 1)
       }"
    )

    create_sql_files() {
      PREVIOUS_VERSION=""
      while IFS= read -r i; do
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
    inherit versions numberOfVersions;
    pname = "${pname}-all";
    version =
      "multi-" + lib.concatStringsSep "-" (map (v: lib.replaceStrings [ "." ] [ "-" ] v) versions);
  };
}
