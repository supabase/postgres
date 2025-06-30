{ inputs, ... }:
{
  imports = [ inputs.treefmt-nix.flakeModule ];
  perSystem =
    { pkgs, ... }:
    {
      treefmt.programs.deadnix.enable = true;

      treefmt.programs.nixfmt.enable = true;
      treefmt.programs.nixfmt.package = pkgs.nixfmt-rfc-style;
    };
}
