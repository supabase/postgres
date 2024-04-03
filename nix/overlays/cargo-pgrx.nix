final: prev: {
  cargo-pgrx_0_11_0 = prev.cargo-pgrx.overrideAttrs (oldAttrs: rec {
    pname = "cargo-pgrx";
    version = "0.11.0";

    src = prev.fetchCrate {
      inherit version pname;
      hash = "sha256-GiUjsSqnrUNgiT/d3b8uK9BV7cHFvaDoq6cUGRwPigM=";
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
      outputHash = "sha256-DB+MQaTj5HWsIxrk5mJblBeGaI4qOuuV24AdjT3ES3o=";
    });
  });

  buildPgrxExtension_0_11_0 = prev.buildPgrxExtension.override {
    cargo-pgrx = final.cargo-pgrx_0_11_0;
  };
}
