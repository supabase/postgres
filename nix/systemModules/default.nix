{
  ...
}:
{
  imports = [ ./tests ];
  flake = {
    systemModules = {
      envoy = ./envoy.nix;
    };
  };
}
