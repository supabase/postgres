{
  ...
}:
{
  imports = [ ./tests ];
  flake = {
    systemModules = {
      fail2ban = ./fail2ban.nix;
    };
  };
}
