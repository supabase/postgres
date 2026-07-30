{
  lib,
  cargo-pgrx,
  fetchCrate,
  makeRustPlatform,
  rust-bin,
  rustVersion ? "1.85.1",
}:
let
  rustPlatform = makeRustPlatform {
    cargo = rust-bin.stable.${rustVersion}.default;
    rustc = rust-bin.stable.${rustVersion}.default;
  };
  mkCargoPgrx =
    args:
    (cargo-pgrx.override { inherit rustPlatform; }).overrideAttrs rec {
      pname = if lib.versionOlder version "0.7.4" then "cargo-pgx" else "cargo-pgrx";
      inherit (args) version;

      src = fetchCrate {
        inherit pname;
        inherit (args)
          version
          hash
          ;
      };

      cargoDeps = rustPlatform.fetchCargoVendor {
        inherit
          pname
          src
          ;
        inherit (args) version;
        hash = args.cargoHash;
      };
    };
in
lib.mapAttrs (_: mkCargoPgrx) {
  cargo-pgrx_0_10_2 = {
    version = "0.10.2";
    hash = "sha256-FqjfbJmSy5UCpPPPk4bkEyvQCnaH9zYtkI7txgIn+ls=";
    cargoHash = "sha256-syZ3cQq8qDHBLvqmNDGoxeK6zXHJ47Jwkw3uhaXNCzI=";
  };
  cargo-pgrx_0_11_3 = {
    version = "0.11.3";
    hash = "sha256-UHIfwOdXoJvR4Svha6ud0FxahP1wPwUtviUwUnTmLXU=";
    cargoHash = "sha256-j4HnD8Zt9uhlV5N7ldIy9564o9qFEqs5KfXHmnQ1WEw=";
  };
  cargo-pgrx_0_12_6 = {
    version = "0.12.6";
    hash = "sha256-7aQkrApALZe6EoQGVShGBj0UIATnfOy2DytFj9IWdEA=";
    cargoHash = "sha256-pnMxWWfvr1/AEp8DvG4awig8zjdHizJHoZ5RJA8CL08=";
  };
  cargo-pgrx_0_12_9 = {
    version = "0.12.9";
    hash = "sha256-aR3DZAjeEEAjLQfZ0ZxkjLqTVMIEbU0UiZ62T4BkQq8=";
    cargoHash = "sha256-yZpD3FriL9UbzRtdFkfIfFfYIrRPYxr/lZ5rb0YBTPc=";
  };
  cargo-pgrx_0_14_3 = {
    version = "0.14.3";
    hash = "sha256-3TsNpEqNm3Uol5XPW1i0XEbP2fF2+RKB2d7lO6BDnvQ=";
    cargoHash = "sha256-LZUXhjMxkBs3O5feH4X5NQC7Qk4Ja6M5+sAYaSCikrY=";
  };
}
// {
  inherit mkCargoPgrx;
}
