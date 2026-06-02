{ inputs, ... }:
{
  imports = [ inputs.treefmt-nix.flakeModule ];
  perSystem = {
    treefmt = {
      programs = {
        deadnix.enable = true;
        gofmt.enable = true;
        nixfmt.enable = true;
        ruff-format.enable = true;
      };

      settings = {
        global.excludes = [
          "*.sum"
          "vendor/*"
        ];
      };
    };
  };
}
