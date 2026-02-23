# Flake-parts module that exposes system-manager configurations
# for security tooling (Tetragon + osquery).
#
# Two profiles:
#   - security-full: osquery + tetragon (instances >= 1GB RAM)
#   - security-lite: osquery only (all instances)
{ inputs, ... }:
{
  flake = {
    systemConfigs = {
      security-full = inputs.system-manager.lib.makeSystemConfig {
        modules = [
          ./osquery.nix
          ./tetragon.nix
          {
            nixpkgs.hostPlatform = "aarch64-linux";
            system-manager.allowAnyDistro = true;
          }
        ];
      };

      security-lite = inputs.system-manager.lib.makeSystemConfig {
        modules = [
          ./osquery.nix
          {
            nixpkgs.hostPlatform = "aarch64-linux";
            system-manager.allowAnyDistro = true;
          }
        ];
      };
    };
  };
}
