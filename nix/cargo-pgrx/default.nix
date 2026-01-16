{
  lib,
  fetchCrate,
  openssl,
  pkg-config,
  makeRustPlatform,
  stdenv,
  rust-bin,
  rustVersion ? "1.85.1",
}:
let
  rustPlatform = makeRustPlatform {
    cargo = rust-bin.stable.${rustVersion}.default;
    rustc = rust-bin.stable.${rustVersion}.default;
  };
  mkCargoPgrx =
    {
      version,
      hash,
      cargoHash,
    }:
    let
      pname = if builtins.compareVersions "0.7.4" version >= 0 then "cargo-pgx" else "cargo-pgrx";
    in
    rustPlatform.buildRustPackage rec {
      # rust-overlay uses 'cargo-auditable' wrapper for 'cargo' command, but it
      # is using older version 0.18.1 of 'cargo_metadata' which doesn't support
      # rust edition 2024, so we disable the 'cargo-auditable' just for now.
      # ref: https://github.com/oxalica/rust-overlay/issues/153
      auditable = false;
      inherit pname;
      inherit version;
      src = fetchCrate { inherit version pname hash; };
      inherit cargoHash;
      nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ pkg-config ];
      buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ openssl ];

      OPENSSL_DIR = "${openssl.dev}";
      OPENSSL_INCLUDE_DIR = "${openssl.dev}/include";
      OPENSSL_LIB_DIR = "${openssl.out}/lib";
      PKG_CONFIG_PATH = "${openssl.dev}/lib/pkgconfig";
      preCheck = ''
        export PGRX_HOME=$(mktemp -d)
      '';
      checkFlags = [
        # requires pgrx to be properly initialized with cargo pgrx init
        "--skip=command::schema::tests::test_parse_managed_postmasters"
      ];
      meta = with lib; {
        description = "Build Postgres Extensions with Rust";
        homepage = "https://github.com/pgcentralfoundation/pgrx";
        changelog = "https://github.com/pgcentralfoundation/pgrx/releases/tag/v${version}";
        license = licenses.mit;
        maintainers = with maintainers; [ happysalada ];
        mainProgram = "cargo-pgrx";
      };
    };
in
{
  cargo-pgrx_0_10_2 = mkCargoPgrx {
    version = "0.10.2";
    hash = "sha256-FqjfbJmSy5UCpPPPk4bkEyvQCnaH9zYtkI7txgIn+ls=";
    cargoHash = "sha256-syZ3cQq8qDHBLvqmNDGoxeK6zXHJ47Jwkw3uhaXNCzI=";
  };
  cargo-pgrx_0_11_3 = mkCargoPgrx {
    version = "0.11.3";
    hash = "sha256-UHIfwOdXoJvR4Svha6ud0FxahP1wPwUtviUwUnTmLXU=";
    cargoHash = "sha256-j4HnD8Zt9uhlV5N7ldIy9564o9qFEqs5KfXHmnQ1WEw=";
  };
  cargo-pgrx_0_12_6 = mkCargoPgrx {
    version = "0.12.6";
    hash = "sha256-7aQkrApALZe6EoQGVShGBj0UIATnfOy2DytFj9IWdEA=";
    cargoHash = "sha256-pnMxWWfvr1/AEp8DvG4awig8zjdHizJHoZ5RJA8CL08=";
  };
  cargo-pgrx_0_12_9 = mkCargoPgrx {
    version = "0.12.9";
    hash = "sha256-aR3DZAjeEEAjLQfZ0ZxkjLqTVMIEbU0UiZ62T4BkQq8=";
    cargoHash = "sha256-yZpD3FriL9UbzRtdFkfIfFfYIrRPYxr/lZ5rb0YBTPc=";
  };
  cargo-pgrx_0_14_3 = mkCargoPgrx {
    version = "0.14.3";
    hash = "sha256-3TsNpEqNm3Uol5XPW1i0XEbP2fF2+RKB2d7lO6BDnvQ=";
    cargoHash = "sha256-LZUXhjMxkBs3O5feH4X5NQC7Qk4Ja6M5+sAYaSCikrY=";
  };
  inherit mkCargoPgrx;
}
