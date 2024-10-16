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
  rustVersion = "1.80.0";
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
  cargo-pgrx_0_12_5 = generic {
    version = "0.12.5";
    hash = "sha256-U2kF+qjQwMTaocv5f4p5y3qmPUsTzdvAp8mz9cn/COw=";
    cargoHash = "sha256-nEgIOBGNG3TupA55/TgoXDPeJzjBjOGGfK+WjrH06VY=";
  };
  inherit rustPlatform;
}