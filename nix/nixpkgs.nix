{ inputs, ... }:
{
  perSystem =
    { system, ... }:
    {
      _module.args.pkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfree = true;
        permittedInsecurePackages = [ "v8-9.7.106.18" ];
        overlays = [
          (
            let
              # Provide older versions of packages required by some extensions
              oldstable = import inputs.nixpkgs-oldstable {
                inherit system;
                config.allowUnfree = true;
              };
            in
            _final: _prev: {
              v8_oldstable = oldstable.v8;
            }
          )
        ];
      };
    };
}
