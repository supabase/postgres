{ self, ... }:
{
  flake.overlays.default = final: prev: {
    # NOTE: add any needed overlays here. in theory we could
    # pull them from the overlays/ directory automatically, but we don't
    # want to have an arbitrary order, since it might matter. being
    # explicit is better.

    inherit (self.packages.${final.system})
      postgresql_15
      postgresql_17
      postgresql_orioledb-17
      supabase-groonga
      switch-ext-version
      ;

    xmrig = throw "The xmrig package has been explicitly disabled in this flake.";

    cargo-pgrx = final.callPackage ../cargo-pgrx/default.nix {
      inherit (final) lib;
      inherit (final) darwin;
      inherit (final) fetchCrate;
      inherit (final) openssl;
      inherit (final) pkg-config;
      inherit (final) makeRustPlatform;
      inherit (final) stdenv;
      inherit (final) rust-bin;
    };

    buildPgrxExtension = final.callPackage ../cargo-pgrx/buildPgrxExtension.nix {
      inherit (final) cargo-pgrx;
      inherit (final) lib;
      inherit (final) Security;
      inherit (final) pkg-config;
      inherit (final) makeRustPlatform;
      inherit (final) stdenv;
      inherit (final) writeShellScriptBin;
    };

    buildPgrxExtension_0_11_2 = prev.buildPgrxExtension.override {
      cargo-pgrx = final.cargo-pgrx.cargo-pgrx_0_11_2;
    };

    buildPgrxExtension_0_11_3 = prev.buildPgrxExtension.override {
      cargo-pgrx = final.cargo-pgrx.cargo-pgrx_0_11_3;
    };

    buildPgrxExtension_0_12_6 = prev.buildPgrxExtension.override {
      cargo-pgrx = final.cargo-pgrx.cargo-pgrx_0_12_6;
    };

    buildPgrxExtension_0_12_9 = prev.buildPgrxExtension.override {
      cargo-pgrx = final.cargo-pgrx.cargo-pgrx_0_12_9;
    };

    buildPgrxExtension_0_14_3 = prev.buildPgrxExtension.override {
      cargo-pgrx = final.cargo-pgrx.cargo-pgrx_0_14_3;
    };
  };
}
