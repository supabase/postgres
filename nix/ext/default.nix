{ ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      packages = {
        sfcgal = pkgs.callPackage ./sfcgal/sfcgal.nix {
          # Use CGAL 5.x for compatibility with current sfcgal version
          cgal = pkgs.cgal_5;
        };
        mecab_naist_jdic = pkgs.callPackage ./mecab-naist-jdic/default.nix { };
      };
    };
}
