{ lib
, darwin
, fetchCrate
, openssl
, pkg-config
, makeRustPlatform
, stdenv
, rust-bin
}:
let
  rustVersion = "1.85.1";
  rustPlatform = makeRustPlatform {
    cargo = rust-bin.stable.${rustVersion}.default;
    rustc = rust-bin.stable.${rustVersion}.default;
  };
  generic =
    { version
    , hash
    , cargoHash
    }:
    rustPlatform.buildRustPackage rec {
      # rust-overlay uses 'cargo-auditable' wrapper for 'cargo' command, but it
      # is using older version 0.18.1 of 'cargo_metadata' which doesn't support
      # rust edition 2024, so we disable the 'cargo-auditable' just for now.
      # ref: https://github.com/oxalica/rust-overlay/issues/153
      auditable = false;
      pname = "cargo-pgrx";
      inherit version;
      src = fetchCrate {
        inherit version pname hash;
      };
      inherit cargoHash;
      nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [
        pkg-config
      ];
      buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
        openssl
      ] ++ lib.optionals stdenv.hostPlatform.isDarwin [
        darwin.apple_sdk.frameworks.Security
      ];
      
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
  cargo-pgrx_0_11_3 = generic {
    version = "0.11.3";
    hash = "sha256-UHIfwOdXoJvR4Svha6ud0FxahP1wPwUtviUwUnTmLXU=";
    cargoHash = "sha256-j4HnD8Zt9uhlV5N7ldIy9564o9qFEqs5KfXHmnQ1WEw=";
  };
  cargo-pgrx_0_12_6 = generic {
    version = "0.12.6";
    hash = "sha256-7aQkrApALZe6EoQGVShGBj0UIATnfOy2DytFj9IWdEA=";
    cargoHash = "sha256-Di4UldQwAt3xVyvgQT1gUhdvYUVp7n/a72pnX45kP0w=";
  };
  cargo-pgrx_0_12_9 = generic {
    version = "0.12.9";
    hash = "sha256-aR3DZAjeEEAjLQfZ0ZxkjLqTVMIEbU0UiZ62T4BkQq8=";
    cargoHash = "sha256-KTKcol9qSNLQZGW32e6fBb6cPkUGItknyVpLdBYqrBY=";
  };
  cargo-pgrx_0_14_3 = generic {
    version = "0.14.3";
    hash = "sha256-3TsNpEqNm3Uol5XPW1i0XEbP2fF2+RKB2d7lO6BDnvQ=";
    cargoHash = "sha256-Ny7j56pwB+2eEK62X0nWfFKQy5fBz+Q1oyvecivxLkk=";
  };
  inherit rustPlatform;
}
