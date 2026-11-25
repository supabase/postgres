{
  lib,
  mkStamped,
  build-ami,
  nix-store-paths,
  postgresMajorVersion,
}:

let
  root = ../..;
  testSources = lib.fileset.toSource {
    inherit root;
    fileset = lib.fileset.unions [
      (root + "/.github/workflows/testinfra-ami-build.yml")
      (root + "/testinfra")
    ];
  };
in
mkStamped {
  name = "ami-test-stamp-${postgresMajorVersion}";
  inputs = {
    inherit build-ami nix-store-paths;
    tests = testSources;
  };
  artifact = "AMI ID";
  pattern = "^ami-[0-9a-f]{8,17}$";
}
