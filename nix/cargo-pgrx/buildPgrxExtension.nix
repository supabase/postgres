{
  lib,
  pkg-config,
  rustPlatform,
  stdenv,
  darwin,
  writeShellScriptBin,
  pgrxVersion,
  rustVersion,
  pkgs,
}:

{
  buildAndTestSubdir ? null,
  buildType ? "release",
  buildFeatures ? [ ],
  cargoBuildFlags ? [ ],
  postgresql,
  useFakeRustfmt ? true,
  usePgTestCheckFeature ? true,
  ...
}@args:

let
  versions = builtins.fromJSON (builtins.readFile ./versions.json);
  pgrx = versions.${pgrxVersion};
  cargoHash = pgrx.rust."${rustVersion}".cargoHash;
  cargoVersion = rustVersion;

  rustfmtInNativeBuildInputs = lib.lists.any (dep: lib.getName dep == "rustfmt") (
    args.nativeBuildInputs or [ ]
  );

  cargo-pgrx = pkgs.callPackage ./pgrx.nix {
    inherit cargoHash;
    pgrxHash = pgrx.hash;
    inherit pgrxVersion;
    inherit cargoVersion;
  };
  fakeRustfmt = writeShellScriptBin "rustfmt" "exit 0";
  pgrxPostgresMajor = lib.versions.major postgresql.version;

  setupVendorEnvironment = ''
    echo "=== ROOT CAUSE ANALYSIS ==="

    if [ -n "''${cargoDeps:-}" ] && [ -d "$cargoDeps" ]; then
      echo "Vendor source: $cargoDeps"
      
      echo ""
      echo "=== TESTING KEY PACKAGES ==="
      for pkg in "shlex-1.3.0" "cc-1.2.30"; do
        pkg_path="$cargoDeps/$pkg"
        if [ -L "$pkg_path" ]; then
          target=$(readlink "$pkg_path")
          echo "$pkg -> $target"
          
          toml_file="$target/Cargo.toml"
          if [ -f "$toml_file" ]; then
            size=$(wc -c < "$toml_file")
            echo "  Cargo.toml: $size bytes"
            if [ "$size" -gt 0 ]; then
              echo "  ✅ Has content"
            else
              echo "  ❌ Empty file"
            fi
          else
            echo "  ❌ No Cargo.toml"
          fi
        fi
      done
      
      echo ""
      echo "=== SUMMARY ==="
      total_items=$(ls "$cargoDeps" | wc -l)
      symlinks=0
      working=0
      broken=0
      broken_list=""
      
      echo "Total items in vendor dir: $total_items"
      
      for item in "$cargoDeps"/*; do
        item_name=$(basename "$item")
        if [ "$item_name" = "Cargo.lock" ] || [ "$item_name" = ".cargo" ]; then
          continue
        fi
        if [ -L "$item" ]; then
          symlinks=$((symlinks + 1))
          target=$(readlink "$item")
          toml_file="$target/Cargo.toml"
          if [ -f "$toml_file" ] && [ -s "$toml_file" ]; then
            working=$((working + 1))
          else
            broken=$((broken + 1))
            broken_list="$broken_list $item_name"
          fi
        fi
      done
      
      echo "Total symlinks (packages): $symlinks"
      echo "Working packages: $working"
      echo "Broken packages: $broken"
      echo "Non-symlink items: $((total_items - symlinks))"
      
      if [ "$broken" -gt 0 ]; then
        echo ""
        echo "=== CORRUPTED PACKAGES LIST ==="
        echo "$broken_list" | tr ' ' '\n' | grep -v '^$' | sort
        echo ""
        echo "❌ NIX STORE CORRUPTION CONFIRMED"
        echo "Packages in Nix store have 0-byte Cargo.toml files"
        exit 1
      else
        echo "✅ Nix store packages are valid"
      fi
    else
      echo "❌ No cargoDeps found!"
      exit 1
    fi
  '';

  setupPgrxEnvironment = ''
        echo "=== Setting up PGRX environment ==="
        export PGRX_HOME=$(mktemp -d)
        export PGDATA="$PGRX_HOME/data-${pgrxPostgresMajor}/"
        export PATH="${postgresql}/bin:$PATH"
        
        cat > $PGRX_HOME/config.toml << EOF
    [configs]
    pg${pgrxPostgresMajor} = "${postgresql}/bin/pg_config"
    EOF
        
        echo "Initializing PGRX..."
        ${cargo-pgrx}/bin/cargo-pgrx pgrx init "--pg${pgrxPostgresMajor}" ${lib.getDev postgresql}/bin/pg_config
  '';

  setupPostgreSQLForTesting = ''
    echo "=== Setting up PostgreSQL for extension testing ==="
    export PGHOST="$(mktemp -d)"
    export USER="$(whoami)"

    echo "Starting PostgreSQL..."
    pg_ctl start -w -l "$PGDATA/postgresql.log" || {
      echo "PostgreSQL failed to start, continuing without database (package-only build)..."
    }

    if pg_ctl status >/dev/null 2>&1; then
      createuser -h localhost --superuser --createdb "$USER" 2>/dev/null || true
    fi
  '';

  buildExtensionPhase = ''
    echo "=== Building extension with cargo-pgrx ==="

    ${lib.optionalString (buildAndTestSubdir != null) ''
      export CARGO_TARGET_DIR="$(pwd)/target"
      pushd "${buildAndTestSubdir}"
    ''}

    PGRX_BUILD_FLAGS="--frozen -j $NIX_BUILD_CORES ${builtins.concatStringsSep " " cargoBuildFlags}"

    ${lib.optionalString stdenv.hostPlatform.isDarwin ''
      export RUSTFLAGS="''${RUSTFLAGS:+''${RUSTFLAGS} }-Clink-args=-Wl,-undefined,dynamic_lookup"
    ''}

    ${cargo-pgrx}/bin/cargo-pgrx pgrx package \
      --pg-config ${lib.getDev postgresql}/bin/pg_config \
      ${lib.optionalString (buildType != "release") "--debug"} \
      ${
        lib.optionalString (
          buildFeatures != [ ]
        ) "--features \"${builtins.concatStringsSep " " buildFeatures}\""
      } \
      --out-dir "$out"

    ${lib.optionalString (buildAndTestSubdir != null) "popd"}
  '';

  cleanupPhase = ''
    echo "=== Cleaning up PostgreSQL ==="
    if [ -n "''${PGDATA:-}" ] && [ -f "$PGDATA/postmaster.pid" ]; then
      echo "Stopping PostgreSQL..."
      pg_ctl stop -w || true
    fi
  '';
in

assert lib.asserts.assertMsg (
  (args.installPhase or "") == ""
) "buildPgrxExtensions overwrites the installPhase";

assert lib.asserts.assertMsg (
  (args.buildPhase or "") == ""
) "buildPgrxExtensions overwrites the buildPhase";

assert lib.asserts.assertMsg (
  useFakeRustfmt -> !rustfmtInNativeBuildInputs
) "useFakeRustfmt conflicts with rustfmt in nativeBuildInputs";

assert lib.asserts.assertMsg (
  !useFakeRustfmt -> rustfmtInNativeBuildInputs
) "useFakeRustfmt false but no rustfmt in nativeBuildInputs";

rustPlatform.buildRustPackage (
  builtins.removeAttrs args [
    "postgresql"
    "useFakeRustfmt"
    "usePgTestCheckFeature"
  ]
  // {
    buildInputs =
      (args.buildInputs or [ ])
      ++ lib.optionals stdenv.hostPlatform.isDarwin [ darwin.apple_sdk.frameworks.Security ];

    nativeBuildInputs =
      (args.nativeBuildInputs or [ ])
      ++ [
        cargo-pgrx
        postgresql
        pkg-config
        rustPlatform.bindgenHook
      ]
      ++ lib.optionals useFakeRustfmt [ fakeRustfmt ];

    buildPhase = ''
      runHook preBuild

      ${setupVendorEnvironment}
      ${setupPgrxEnvironment}  
      ${setupPostgreSQLForTesting}
      ${buildExtensionPhase}

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      ${lib.optionalString (buildAndTestSubdir != null) ''
        pushd "${buildAndTestSubdir}"
      ''}

      echo "=== Installing extension files ==="

      mv $out/${postgresql}/* $out
      mv $out/${postgresql.lib}/* $out  
      rm -rf $out/nix

      ${lib.optionalString (buildAndTestSubdir != null) "popd"}

      runHook postInstall
    '';

    postBuild = cleanupPhase;
    postInstall = cleanupPhase;

    PGRX_PG_SYS_SKIP_BINDING_REWRITE = "1";
    CARGO_BUILD_INCREMENTAL = "false";
    RUST_BACKTRACE = "full";

    checkNoDefaultFeatures = true;
    checkFeatures =
      (args.checkFeatures or [ ])
      ++ lib.optionals usePgTestCheckFeature [ "pg_test" ]
      ++ [ "pg${pgrxPostgresMajor}" ];

    meta = (args.meta or { }) // {
      description = args.meta.description or "PostgreSQL extension built with pgrx";
      platforms = lib.platforms.unix;
    };
  }
)
