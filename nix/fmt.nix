{ inputs, ... }:
{
  imports = [ inputs.treefmt-nix.flakeModule ];
  perSystem =
    { pkgs, ... }:
    {
      treefmt.programs = {
        deadnix.enable = true;
        nixfmt = {
          enable = true;
          package = pkgs.nixfmt-rfc-style;
        };
        ruff-format.enable = true;
      };
    };
}
