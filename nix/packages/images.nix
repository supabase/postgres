{
  perSystem =
    {
      lib,
      pkgs,
      self',
      ...
    }:
    let
      makeAmiTestStamp =
        version:
        pkgs.callPackage ./ami-test-stamp.nix {
          inherit (self'.packages) build-ami;
          nix-store-paths = self'.packages."nix-store-paths-${version}";
          postgresMajorVersion = version;
        };
    in
    {
      packages = {
        ami-test-stamp-15 = makeAmiTestStamp "15";
        ami-test-stamp-17 = makeAmiTestStamp "17";
        ami-test-stamp-orioledb-17 = makeAmiTestStamp "orioledb-17";
        build-ami = pkgs.callPackage ./build-ami { inherit (self'.packages) packer; };
        build-qemu-image = pkgs.callPackage ./build-qemu-image { inherit (self'.packages) packer; };
      };
      legacyPackages = lib.optionalAttrs pkgs.stdenv.isLinux {
        inherit (self'.packages) build-ami build-qemu-image;
      };
    };
}
