final: prev: {
  cargo-pgrx_0_10_2 = prev.cargo-pgrx.overrideAttrs (oldAttrs: rec {
    pname = "cargo-pgrx";
    version = "0.10.2";

    src = prev.fetchCrate {
      inherit version pname;
      hash = "sha256-FqjfbJmSy5UCpPPPk4bkEyvQCnaH9zYtkI7txgIn+ls=";
    };

    # NOTE (aseipp): normally, we would just use 'cargoHash' here, but
    # due to a fantastic interaction of APIs, we can't do that so
    # easily, and have to use this incantation instead, which is
    # basically the exact same thing but with 4 extra lines. see:
    #
    # https://discourse.nixos.org/t/is-it-possible-to-override-cargosha256-in-buildrustpackage/4393/5
    cargoDeps = oldAttrs.cargoDeps.overrideAttrs (prev.lib.const {
      name = "${pname}-vendor.tar.gz";
      inherit src;
      outputHash = "sha256-0blBUEm8PPbDyF+NnSwoMJpu+a20zq1/2+dzP0H9i+E=";
    });
  });

  buildPgrxExtension_0_10_2 = prev.buildPgrxExtension.override {
    cargo-pgrx = final.cargo-pgrx_0_10_2;
  };
}
