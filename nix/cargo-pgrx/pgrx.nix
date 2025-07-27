{
  pkgs,
  pgrxHash,
  cargoHash,
  pgrxVersion,
  cargoVersion,
  postgresql,

}:

let
  lib = pkgs.lib;

  rustPlatform = pkgs.makeRustPlatform {
    cargo = pkgs.rust-bin.stable.${cargoVersion}.default;
    rustc = pkgs.rust-bin.stable.${cargoVersion}.default;
  };
in

rustPlatform.buildRustPackage rec {
  auditable = false;
  pname = "cargo-pgrx";
  version = pgrxVersion;

  src = pkgs.fetchFromGitHub {
    owner = "pgcentralfoundation";
    repo = "pgrx";
    rev = builtins.trace "TRACE pgrx.nix: fetching pgrx rev = v${pgrxVersion}" "v${pgrxVersion}";
    hash = builtins.trace "TRACE pgrx.nix: using pgrxHash = ${pgrxHash}" pgrxHash;
  };
  inherit cargoHash;

  # Add this right after the src definition
  postUnpack = ''
      echo "=== TOOLCHAIN DEBUG ==="
    echo "Rust version: $(rustc --version)"
    echo "Cargo version: $(cargo --version)"
    echo "PWD: $(pwd)"
    echo "Rust location: $(which rustc)"
    echo "Cargo location: $(which cargo)"
    echo "=== Patching lockfile version before vendoring ==="
    echo "Original lockfile:"
    head -5 source/Cargo.lock

    # Patch lockfile version from 4 to 3
    sed -i 's/version = 4/version = 3/' source/Cargo.lock

    echo "Patched lockfile:"
    head -5 source/Cargo.lock
  '';

  nativeBuildInputs = [
    pkgs.pkg-config
    postgresql
  ];

  buildInputs = [
    pkgs.openssl
  ] ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin [ pkgs.darwin.apple_sdk.frameworks.Security ];

  OPENSSL_DIR = "${pkgs.openssl.dev}";
  OPENSSL_INCLUDE_DIR = "${pkgs.openssl.dev}/include";
  OPENSSL_LIB_DIR = "${pkgs.openssl.out}/lib";
  PKG_CONFIG_PATH = "${pkgs.openssl.dev}/lib/pkgconfig";
  PGRX_PG_SYS_SKIP_BINDING_REWRITE = "1";
  RUST_BACKTRACE = "full";

  pgrxPostgresMajor = lib.versions.major postgresql.version;
  buildFeatures = [ "pg${pgrxPostgresMajor}" ];

  doCheck = false;

  preBuild = ''
    echo "=== TOOLCHAIN DEBUG ==="
    echo "Rust version: $(rustc --version)"
    echo "Cargo version: $(cargo --version)"
    echo "PWD: $(pwd)"
    echo "Rust location: $(which rustc)"
    echo "Cargo location: $(which cargo)"

    echo ""
    echo "=== LOCKFILE DEBUG ==="
    echo "Cargo.lock location and content:"
    find . -name "Cargo.lock" -exec echo "Found: {}" \; -exec head -5 {} \;

    echo ""
    echo "=== ENVIRONMENT ==="
    echo "RUSTFLAGS: ''${RUSTFLAGS:-<not set>}"
    echo "CARGO_BUILD_TARGET: ''${CARGO_BUILD_TARGET:-<not set>}"

    echo ""
    echo "=== TEST BASIC CARGO COMMAND ==="
    if cargo check --version 2>&1; then
      echo "✅ Cargo responds to basic commands"
    else
      echo "❌ Cargo basic command failed"
    fi

    echo ""
    echo "=== TRY PARSING LOCKFILE ==="
    if cargo tree --offline --quiet 2>&1; then
      echo "✅ Cargo can parse lockfile"
    else
      echo "❌ Cargo lockfile parse failed"
    fi
  '';

  buildPhase = ''
        runHook preBuild
        
        export PGRX_HOME=$(mktemp -d)
        export PATH="${postgresql}/bin:$PATH"
        cat > $PGRX_HOME/config.toml << EOF
    [configs]
    pg${pgrxPostgresMajor} = "${postgresql}/bin/pg_config"
    EOF

        echo "=== DEBUG: Checking build directory contents ==="
        ls -la /build/
        
        echo "=== Creating and copying vendor directory to expected location ==="
        mkdir -p /build/cargo-vendor-dir
        
        # Check if vendor tarball exists and extract it
        VENDOR_TARBALL="/build/cargo-pgrx-${pgrxVersion}-vendor.tar.gz"
        if [ -f "$VENDOR_TARBALL" ]; then
          echo "Found vendor tarball at $VENDOR_TARBALL"
          cd /build
          tar -xzf "cargo-pgrx-${pgrxVersion}-vendor.tar.gz"
          
          # Find the extracted directory (might have different name)
          VENDOR_DIR=$(find /build -maxdepth 1 -name "*vendor*" -type d | head -1)
          if [ -n "$VENDOR_DIR" ] && [ "$VENDOR_DIR" != "/build/cargo-vendor-dir" ]; then
            echo "Copying from $VENDOR_DIR to /build/cargo-vendor-dir/"
            cp -r "$VENDOR_DIR"/* /build/cargo-vendor-dir/
          else
            echo "No vendor directory found after extraction"
          fi
        else
          echo "No vendor tarball found, checking for existing vendor directory..."
          
          # Look for any vendor-related directories
          find /build -name "*vendor*" -type d
          
          # Use Nix's default cargo vendor setup if available
          if [ -d "/build/source/vendor" ]; then
            echo "Using source vendor directory"
            cp -r /build/source/vendor/* /build/cargo-vendor-dir/
          elif [ -d "/build/vendor" ]; then
            echo "Using build vendor directory"  
            cp -r /build/vendor/* /build/cargo-vendor-dir/
          else
            echo "No vendor directory found, proceeding with normal build"
          fi
        fi

        echo "=== DEBUG: Looking for shlex in vendor directory ==="
        find /build/cargo-vendor-dir -name "*shlex*" -type d 2>/dev/null || echo "No shlex directories found"
        find /build/cargo-vendor-dir -name "*shlex*" -type f 2>/dev/null || echo "No shlex files found"
        
        echo "=== DEBUG: Check what shlex directories exist ==="
        ls -la /build/cargo-vendor-dir/ | grep shlex || echo "No shlex entries found"
        
        echo "=== DEBUG: If shlex-1.3.0 exists, check its contents ==="
        if [ -d "/build/cargo-vendor-dir/shlex-1.3.0" ]; then
          ls -la /build/cargo-vendor-dir/shlex-1.3.0/
        else
          echo "shlex-1.3.0 directory not found"
        fi
        
        echo "=== Building cargo-pgrx ==="
        # Try offline build first, fall back to online if needed
        if ! cargo build --release --frozen --offline --package cargo-pgrx; then
          echo "Offline build failed, trying online build..."
          cargo build --release --package cargo-pgrx
        fi
        
        runHook postBuild
  '';

  preCheck = ''export PGRX_HOME=$(mktemp -d)'';
  checkFlags = [ "--skip=command::schema::tests::test_parse_managed_postmasters" ];
  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin

    # Install the binary
    if [ -f target/release/cargo-pgrx ]; then
      cp target/release/cargo-pgrx $out/bin/
      chmod +x $out/bin/cargo-pgrx
    else
      echo "ERROR: Could not find cargo-pgrx binary"
      exit 1
    fi

    runHook postInstall
  '';
  meta = with lib; {
    description = "Build Postgres Extensions with Rust";
    homepage = "https://github.com/pgcentralfoundation/pgrx";
    license = licenses.mit;
    mainProgram = "cargo-pgrx";
  };
}
