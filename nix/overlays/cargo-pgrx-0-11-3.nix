final: prev: {
  #cargo-pgrx_0_11_3 = cargo-pgrx.cargo-pgrx_0_11_3;

  buildPgrxExtension_0_11_3 = prev.buildPgrxExtension.override {
    cargo-pgrx = final.cargo-pgrx_0_11_3;
  };
}
