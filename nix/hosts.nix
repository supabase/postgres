{ inputs, self, ... }:
{
  flake = {
    darwinConfigurations = {
      darwin-nixostest = inputs.nix-darwin.lib.darwinSystem {
        specialArgs = { inherit self inputs; };
        modules = [ ./hosts/darwin-nixostest/darwin-configuration.nix ];
      };
    };
  };
}
