{ ... }:
{
  perSystem =
    {
      inputs',
      config,
      lib,
      pkgs,
      ...
    }:
    {
      packages = {
        sfcgal = pkgs.callPackage ./sfcgal/sfcgal.nix { };
        mecab_naist_jdic = pkgs.callPackage ./mecab-naist-jdic/default.nix { };
      };
    };
}
