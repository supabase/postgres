{
  lib,
  stdenv,
  fetchFromGitHub,
  openssl,
  pkg-config,
  makeRustPlatform,
  rust-bin,
  postgresql,
}:
let
  pgrxPostgresMajor = lib.versions.major postgresql.version;

  versions = builtins.fromJSON (builtins.readFile ./versions.json);

  # See the versions.json file for the available versions
  rustVersionMapping = {
    "0.11.3" = "1.85.1";
    "0.12.6" = "1.81.0";
    "0.12.9" = "1.87.0";
    "0.14.3" = "1.87.0";
  };

  mkPgrx =
    pgrxVersion:
    let
      rustVersion = rustVersionMapping.${pgrxVersion};
      pgrx = versions.${pgrxVersion};
      cargoHash = pgrx.rust.${rustVersion}.cargoHash;

      rustPlatform = makeRustPlatform {
        cargo = rust-bin.stable.${rustVersion}.default;
        rustc = rust-bin.stable.${rustVersion}.default;
      };
    in
    rustPlatform.buildRustPackage {
      pname = "cargo-pgrx";
      version = pgrxVersion;

      src = fetchFromGitHub {
        owner = "pgcentralfoundation";
        repo = "pgrx";
        rev = "v${pgrxVersion}";
        inherit (pgrx) hash;
      };

      inherit cargoHash;

      nativeBuildInputs = [
        pkg-config
        postgresql
      ];
      buildInputs = [
        openssl
      ] ++ lib.optionals stdenv.hostPlatform.isDarwin [ stdenv.cc.bintools.bintools_bin ];

      preCheck = ''export PGRX_HOME=$(mktemp -d)'';

      # Environment variables
      OPENSSL_DIR = "${openssl.dev}";
      OPENSSL_INCLUDE_DIR = "${openssl.dev}/include";
      OPENSSL_LIB_DIR = "${openssl.out}/lib";
      PKG_CONFIG_PATH = "${openssl.dev}/lib/pkgconfig";
      PGRX_PG_SYS_SKIP_BINDING_REWRITE = "1";
      RUST_BACKTRACE = "full";

      buildPhase = ''
        runHook preBuild

        export PATH="${postgresql}/bin:$PATH"
        cat > $PGRX_HOME/config.toml << EOF
        [configs]
        pg${pgrxPostgresMajor} = "${postgresql}/bin/pg_config"
        EOF

        cargo build --release --frozen --offline --package cargo-pgrx

        runHook postBuild
      '';

      installPhase = ''
        runHook preInstall

        mkdir -p $out/bin
        cp target/release/cargo-pgrx $out/bin/
        chmod +x $out/bin/cargo-pgrx

        runHook postInstall
      '';

      doCheck = false;

      meta = with lib; {
        description = "Build Postgres Extensions with Rust";
        homepage = "https://github.com/pgcentralfoundation/pgrx";
        license = licenses.mit;
        mainProgram = "cargo-pgrx";
      };
    };
in
{
  cargo-pgrx_0_11_3 = mkPgrx "0.11.3";
  cargo-pgrx_0_12_6 = mkPgrx "0.12.6";
  cargo-pgrx_0_12_9 = mkPgrx "0.12.9";
  cargo-pgrx_0_14_3 = mkPgrx "0.14.3";
}
