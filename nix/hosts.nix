{ inputs, ... }:
{
  flake = {
    darwinConfigurations = {
      darwin-nixostest = inputs.nix-darwin.lib.darwinSystem {
        modules = [ ./hosts/darwin-nixostest/darwin-configuration.nix ];
      };
    };
  };
}
