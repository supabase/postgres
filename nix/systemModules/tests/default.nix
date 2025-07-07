{ self, ... }:
{
  perSystem =
    { lib, pkgs, ... }:
    {
      checks = lib.optionalAttrs (pkgs.stdenv.hostPlatform.isLinux) {
        ubuntu-postgres = (import ./postgres.nix { inherit self pkgs; }).sandboxed;
      };
    };
}
