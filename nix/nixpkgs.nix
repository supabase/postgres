{ self, inputs, ... }:
{
  perSystem =
    { system, ... }:
    {
      _module.args.pkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfree = true;
        config.permittedInsecurePackages = [
          "curl-8.6.0"
          "v8-9.7.106.18"
        ];
        overlays = [
          (import inputs.rust-overlay)
          self.overlays.default
          (_final: _prev: {
            curl_8_6 = _prev.callPackage ./packages/curl-8_6 { };
            v8_9_7_106 = _prev.callPackage ./packages/v8-9_7_106 { };
          })
          inputs.devshell.overlays.default
        ];
      };
    };
}
