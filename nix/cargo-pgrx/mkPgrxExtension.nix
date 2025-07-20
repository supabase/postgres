{
  callPackage,
  rustVersion,
  pgrxVersion,
  makeRustPlatform,
  rust-bin,
}:
let
  rustPlatform = makeRustPlatform {
    cargo = rust-bin.stable.${rustVersion}.default;
    rustc = rust-bin.stable.${rustVersion}.default;
  };

  buildPgrxExtension = callPackage ./buildPgrxExtension.nix {
    inherit rustPlatform;
    pgrxVersion = builtins.trace "TRACE mkPgrxExtension: pgrxVersion = ${pgrxVersion}" pgrxVersion;
    rustVersion = builtins.trace "TRACE mkPgrxExtension: rustVersion = ${rustVersion}" rustVersion;
  };

in
buildPgrxExtension
