{
  callPackage,
  rustVersion,
  pgrxVersion,
  makeRustPlatform,
  rust-bin,
}:
let
  inherit
    (
      (callPackage ./default.nix {
        inherit rustVersion;
      })
    )
    mkCargoPgrx
    ;

  rustPlatform = makeRustPlatform {
    cargo = rust-bin.stable.${rustVersion}.default;
    rustc = rust-bin.stable.${rustVersion}.default;
  };

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
in
callPackage ./buildPgrxExtension.nix {
  inherit rustPlatform;
  inherit cargo-pgrx;
}
