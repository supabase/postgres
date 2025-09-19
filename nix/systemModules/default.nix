{
  ...
}:
{
  imports = [ ./tests ];
  flake = {
    systemModules = {
      postgres = ./postgres;
      pgbouncer = ./pgbouncer.nix;
    };
  };
}
