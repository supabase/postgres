{
  lib,
  pkgs,
  cargo-pgrx,
  fetchCrate,
  makeRustPlatform,
  rust-bin,
  rustVersion ? "1.85.1",
}:
let
  # TODO: remove once nixpkgs is bumped past NixOS/nixpkgs#512735
  rustPlatform = import ./fix-cargo.nix { inherit pkgs; } (makeRustPlatform {
    cargo = rust-bin.stable.${rustVersion}.default;
    rustc = rust-bin.stable.${rustVersion}.default;
  });
in
{
  mkCargoPgrx =
    {
      version,
      hash,
      cargoHash,
    }:
    (cargo-pgrx.override { inherit rustPlatform; }).overrideAttrs (old: rec {
      # https://github.com/oxalica/rust-overlay/issues/153
      auditable = false;

      pname = if lib.versionOlder version "0.7.4" then "cargo-pgx" else "cargo-pgrx";
      inherit version;

      # TODO: remove once nixpkgs is bumped past NixOS/nixpkgs#512735
      src = fetchCrate {
        inherit pname version hash;
        registryDl = "https://static.crates.io/crates";
      };

      cargoDeps = rustPlatform.fetchCargoVendor {
        inherit pname src version;
        hash = cargoHash;
      };

      checkFlags = (old.checkFlags or [ ]) ++ [
        "--skip=object_utils::tests::parses_managed_postmasters"
        # require test fixtures not included in the crates.io source tarball
        "--skip=command::upgrade::tests::find_package_manifest_in_workspace"
        "--skip=command::upgrade::tests::process_workspace_manifest"
        "--skip=command::upgrade::tests::process_workspace_package_manifest"
      ];
    });
}
