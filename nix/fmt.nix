{ inputs, lib, ... }:
{
  imports = [ inputs.treefmt-nix.flakeModule ];
  perSystem =
    { config, pkgs, ... }:
    {
      treefmt = {
        programs = {
          deadnix.enable = true;
          gofmt.enable = true;
          nixfmt.enable = true;
          packer.enable = true;
          ruff-format.enable = true;
          shfmt.enable = true;
          shfmt.indent_size = null; # use shfmt's default width (tab)
        };

        settings = {
          formatter.oxfmt = {
            command =
              assert lib.assertMsg (
                !(config.treefmt.programs ? oxfmt)
              ) "treefmt-nix now has an oxfmt module; replace this formatter with programs.oxfmt";
              "${pkgs.oxfmt}/bin/oxfmt";
            includes = [ "renovate.json5" ];
          };
        };
      };
    };
}
