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
    inherit pgrxVersion;
    inherit rustVersion;
  };
in
buildPgrxExtension
