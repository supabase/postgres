{
  flake-parts-lib,
  withSystem,
  self,
  ...
}:
{
  imports = [ ./tests ];
  flake = {
    systemModules = {
      postgres = flake-parts-lib.importApply ./postgres.nix { inherit withSystem self; };
    };
  };
}
