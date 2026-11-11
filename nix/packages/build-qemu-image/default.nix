{
  lib,
  cloud-utils,
  coreutils,
  gitMinimal,
  packer,
  qemu,
  writeShellApplication,
  yq,
}:
let
  root = ../../..;
  qemuSources = lib.fileset.toSource {
    inherit root;
    fileset = lib.fileset.unions [
      (root + "/ansible")
      (root + "/audit-specs")
      (root + "/migrations/db")
      (root + "/packer")
      ./meta-data
      ./user-data-cloudimg
    ];
  };
in
writeShellApplication {
  name = "build-qemu-image";

  runtimeInputs = [
    cloud-utils
    coreutils
    gitMinimal
    packer
    qemu
    yq
  ];

  text = lib.replaceStrings [ "@qemuSources@" ] [ (toString qemuSources) ] (
    builtins.readFile ./build-qemu-image.sh
  );
}
