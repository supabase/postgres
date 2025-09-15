{ lib, ... }:
{
  options.networking.firewall = lib.mkOption {
    type = lib.types.attrs;
  };
}
