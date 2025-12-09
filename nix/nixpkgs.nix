{ self, inputs, ... }:
{
  perSystem =
    { system, ... }:
    {
      _module.args.pkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfree = true;
        permittedInsecurePackages = [ "v8-9.7.106.18" ];
        overlays = [
          (import inputs.rust-overlay)
          self.overlays.default
          (_final: _prev: {
            # Provide older versions of packages required by some extensions
            oldstable = import inputs.nixpkgs-oldstable {
              inherit system;
              config.allowUnfree = true;
            };
            curl_8_6 =
              (import inputs.nixpkgs-oldstable {
                inherit system;
                config.allowUnfree = true;
              }).curl;
            v8_oldstable =
              (import inputs.nixpkgs-oldstable {
                inherit system;
                config.allowUnfree = true;
              }).v8;
          })
        ];
      };
    };
}
