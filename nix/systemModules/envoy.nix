{
  lib,
  nixosModulesPath,
  self,
  system,
  ...
}:
{
  imports = map (path: nixosModulesPath + path) [
    "/services/networking/envoy.nix"
  ];
  config = {
    services.envoy = {
      enable = true;
      package = self.packages.${system}.envoy-bin;
      # TODO: settings from postgres/ansible/files/envoy_config/
    };
    systemd.services.envoy = {
      wantedBy = lib.mkForce [
        "system-manager.target"
      ];
    };
  };
}
