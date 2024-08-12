final: prev: {
  buildPgrxWrappers = prev.callPackage ../cargo-pgrx/buildPgrxWrappers.nix {
    inherit (prev.darwin.apple_sdk.frameworks) Security;
  };

  buildPgrxWrappers_0_11_3 = final.buildPgrxWrappers.override {
    cargo-pgrx = final.cargo-pgrx_0_11_3;
  };
}