{ ... }:
{
  perSystem =
    { pkgs, inputs', ... }:
    {
      packages = {
        # Built from plain nixpkgs, without our overlays.
        # With the old tzdata hash still in place this would fail to build so could not update tzdata hash.
        rehash = inputs'.nixpkgs.legacyPackages.callPackage ./rehash { };
        update-ansible-artifacts = pkgs.callPackage ./update-ansible-artifacts { };
      };
    };
}
