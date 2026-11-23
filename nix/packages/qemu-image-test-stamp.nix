{
  lib,
  mkStamped,
  build-qemu-image,
  nix-store-paths,
  postgresMajorVersion,
}:

let
  root = ../..;
  testSources = lib.fileset.toSource {
    inherit root;
    fileset = lib.fileset.unions [
      (root + "/.github/workflows/qemu-image-build.yml")
      (root + "/Dockerfile-kubernetes")
    ];
  };
in
# The out path is per system, so it covers the guest architecture as well.
mkStamped {
  name = "qemu-image-test-stamp-${postgresMajorVersion}";
  inputs = {
    inherit build-qemu-image nix-store-paths;
    tests = testSources;
  };
  artifact = "image digest";
  pattern = "^[0-9a-f]{64}$";
}
