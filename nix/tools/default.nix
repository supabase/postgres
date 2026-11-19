{ ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      packages = {
        rehash = pkgs.callPackage ./rehash { };
        update-ansible-artifacts = pkgs.callPackage ./update-ansible-artifacts { };
      };
    };
}
