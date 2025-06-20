{ self, inputs, ... }:
{
  perSystem =
    { system, ... }:
    {
      _module.args.pkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfree = true;
        permittedInsecurePackages = [
          "v8-9.7.106.18"
        ];
        overlays = [
          (import inputs.rust-overlay)
          self.overlays.default
        ];
      };
    };
}
