{ inputs, ... }:
{
  imports = [ inputs.treefmt-nix.flakeModule ];
  perSystem = _: {
    treefmt = {
      programs = {
        deadnix.enable = true;
        gofmt.enable = true;
        nixfmt.enable = true;
        oxfmt.enable = true;
        oxfmt.includes = [
          "*.json"
          "*.json5"
          "*.md"
          "*.toml"
          "*.yaml"
          "*.yml"
        ];
        packer.enable = true;
        ruff-format.enable = true;
        shfmt.enable = true;
        shfmt.indent_size = null; # use shfmt's default width (tab)
      };
    };
  };
}
