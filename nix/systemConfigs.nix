{ self, inputs, ... }:
let
  mkModules = system: [
    self.systemModules.ssh-config
    self.systemModules.logrotate
    ({
      nixpkgs.hostPlatform = system;
      supabase.services.logrotate.enable = true;
    })
  ];

  systems = [
    "aarch64-linux"
    "x86_64-linux"
  ];

  mkSystemConfig = system: {
    name = system;
    value.default = inputs.system-manager.lib.makeSystemConfig {
      modules = mkModules system;
      extraSpecialArgs = {
        inherit self;
        inherit system;
      };
    };
  };
in
{
  flake = {
    systemConfigs = builtins.listToAttrs (map mkSystemConfig systems);
  };
}
