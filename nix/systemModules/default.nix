{
  ...
}:
{
  imports = [ ./tests ];
  flake = {
    systemModules = {
      postgres = ./postgres;
      gotrue = ./gotrue.nix;
    };
  };
}
