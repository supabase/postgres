{ self, ... }:
{
  perSystem =
    {
      lib,
      system,
      pkgs,
      ...
    }:
    {
      checks = pkgs.lib.optionalAttrs (system == "x86_64-linux") {
        systemModulePostgres = import ./postgres.nix { inherit self pkgs; };
      };
    };
}
