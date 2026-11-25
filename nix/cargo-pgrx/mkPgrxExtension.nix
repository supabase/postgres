{
  lib,
  pkgs,
  callPackage,
  clang11,
  rustVersion,
  pgrxVersion,
  makeRustPlatform,
  rust-bin,
}:
let
  inherit ((callPackage ./default.nix { inherit rustVersion rust-bin; })) mkCargoPgrx;

  # TODO: drop the fix-cargo.nix import once nixpkgs is bumped past NixOS/nixpkgs#512735
  rustPlatform = import ./fix-cargo.nix { inherit pkgs; } (
    import ./crate-fetchurl.nix (makeRustPlatform {
      cargo = rust-bin.stable.${rustVersion}.default;
      rustc = rust-bin.stable.${rustVersion}.default;
    })
  );

  versions = builtins.fromJSON (builtins.readFile ./versions.json);

  cargo-pgrx =
    let
      pgrx =
        versions.${pgrxVersion}
          or (throw "Unsupported pgrx version ${pgrxVersion}. Available versions: ${builtins.toString (builtins.attrNames versions)}. Change 'nix/cargo-pgrx/versions.json' to add support for new versions.");
      mapping = {
        inherit (pgrx) hash;
        cargoHash =
          pgrx.rust."${rustVersion}".cargoHash
            or (throw "Unsupported rust version ${rustVersion} for pgrx version ${pgrxVersion}. Available Rust versions: ${builtins.toString (builtins.attrNames pgrx.rust)}. Change 'nix/cargo-pgrx/versions.json' to add support for new versions.");
      };
    in
    mkCargoPgrx {
      inherit (mapping) hash cargoHash;
      version = pgrxVersion;
    };

  bindgenHook =
    # pgrx 0.6.1 through 0.11.2 use old bindgen versions that break with current clang and glibc:
    # - bindgen 0.60.x panics on how clang 16+ names anonymous structs
    #   ("(unnamed at /path/file.h:N:M)"), which glibc and macOS SDK headers contain.
    # - on aarch64-linux, bindgen fails on the ARM NEON vector functions that newer glibc headers declare.
    # So build them with clang and glibc headers from nixos-22.11, on every platform.
    if lib.versionOlder pgrxVersion "0.11.3" then
      rustPlatform.bindgenHook.overrideAttrs {
        libclang = clang11.cc.lib;
        clang = clang11;
      }
    else
      rustPlatform.bindgenHook;
in
callPackage ./buildPgrxExtension.nix {
  inherit rustPlatform;
  inherit cargo-pgrx;
  defaultBindgenHook = bindgenHook;
}
