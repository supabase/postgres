{ self, inputs, ... }:
let
  mkModules = system: [
    self.systemModules.envoy
    ({
      services.nginx.enable = true;
      nixpkgs.hostPlatform = system;
      supabase.services.envoy = {
        enable = true;
        enableTLS = true;
      };
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
