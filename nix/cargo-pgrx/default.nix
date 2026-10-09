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
    args:
    (cargo-pgrx.override { inherit rustPlatform; }).overrideAttrs (old: rec {
      # https://github.com/oxalica/rust-overlay/issues/153
      auditable = false;

      pname = if lib.versionOlder version "0.7.4" then "cargo-pgx" else "cargo-pgrx";
      inherit (args) version;

      # TODO: remove once nixpkgs is bumped past NixOS/nixpkgs#512735
      src = fetchCrate {
        inherit pname;
        inherit (args) version hash;
        registryDl = "https://static.crates.io/crates";
      };

      cargoDeps = rustPlatform.fetchCargoVendor {
        inherit pname src;
        inherit (args) version;
        hash = args.cargoHash;
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
