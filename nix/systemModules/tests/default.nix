{ self, ... }:
{
  perSystem =
    { lib, pkgs, ... }:
    {
      packages = lib.optionalAttrs (pkgs.stdenv.hostPlatform.isLinux) {
        check-system-manager-nginx = (import ./nginx.nix { inherit self pkgs; });
      };
    };
}
