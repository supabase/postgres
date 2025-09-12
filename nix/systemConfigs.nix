{ self, inputs, ... }:
let
  mkModules = system: [
    self.systemModules.postgres
    ({
      services.nginx.enable = true;
      nixpkgs.hostPlatform = system;
      supabase.services.postgres = {
        enable = true;
        package = self.packages.${system}."psql_17/bin";
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
