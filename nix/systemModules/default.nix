{
  ...
}:
{
  imports = [ ./tests ];
  flake = {
    systemModules = {
      postgres = ./postgres;
    };
  };
}
