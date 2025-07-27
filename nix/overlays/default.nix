{ self, ... }:
{
  flake.overlays.default = final: _prev: {
    inherit (self.packages.${final.system})
      postgresql_15
      postgresql_17
      postgresql_orioledb-17
      supabase-groonga
      ;

    xmrig = throw "The xmrig package has been explicitly disabled in this flake.";

    buildPgrxExtension_0_12_6 = final.callPackage ../cargo-pgrx/mkPgrxExtension.nix {
      rustVersion = "1.81.0";
      pgrxVersion = "0.12.6";
    };

    buildPgrxExtension_0_12_9 = final.callPackage ../cargo-pgrx/mkPgrxExtension.nix {
      rustVersion = "1.87.0";
      pgrxVersion = "0.12.9";
    };
  };
}
