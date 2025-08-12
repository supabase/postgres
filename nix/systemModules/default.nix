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
      nginx = flake-parts-lib.importApply ./nginx.nix { inherit withSystem self; };
    };
  };
}
