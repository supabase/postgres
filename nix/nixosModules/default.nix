{
  flake-parts-lib,
  withSystem,
  ...
}:
{
  imports = [ ./tests ];
  flake = {
    nixosModules = {
      postgres = flake-parts-lib.importApply ./postgres.nix {
        inherit withSystem;
      };
    };
  };
}
