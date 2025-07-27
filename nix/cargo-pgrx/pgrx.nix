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
    rev = pgrxVersion;
    hash = pgrxHash;
  };

  inherit cargoHash;

  postUnpack = ''
    # Patch lockfile version from 4 to 3
    sed -i 's/version = 4/version = 3/' source/Cargo.lock
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

  buildPhase = ''
        runHook preBuild
        
        export PGRX_HOME=$(mktemp -d)
        export PATH="${postgresql}/bin:$PATH"
        cat > $PGRX_HOME/config.toml << EOF
    [configs]
    pg${pgrxPostgresMajor} = "${postgresql}/bin/pg_config"
    EOF

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
    cp target/release/cargo-pgrx $out/bin/
    chmod +x $out/bin/cargo-pgrx

    runHook postInstall
  '';

  meta = with lib; {
    description = "Build Postgres Extensions with Rust";
    homepage = "https://github.com/pgcentralfoundation/pgrx";
    license = licenses.mit;
    mainProgram = "cargo-pgrx";
  };
}
