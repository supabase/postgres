{
  awscli2,
  cdrkit,
  coldsnap,
  coreutils,
  fetchurl,
  gitMinimal,
  qemu,
  writeShellApplication,
  yq,
}:
let
  release = "https://cloud-images.ubuntu.com/releases/noble/release-20260926";
in
writeShellApplication {
  name = "build-ami-qemu";

  runtimeInputs = [
    awscli2
    cdrkit
    coldsnap
    coreutils
    gitMinimal
    qemu
    yq
  ];

  runtimeEnv = {
    CLOUDIMG_AMD64 = fetchurl {
      url = "${release}/ubuntu-24.04-server-cloudimg-amd64.img";
      sha256 = "6a81c37564db9b1ee84e141922625e1d7c5b389b99bb3c572e0243607d5bb4d2";
    };
    CLOUDIMG_ARM64 = fetchurl {
      url = "${release}/ubuntu-24.04-server-cloudimg-arm64.img";
      sha256 = "1d6bffe64b848468ac97f821d369a4846d983de1800ccf6b5ec8853e85cefc55";
    };
  };

  text = builtins.readFile ./build-ami-qemu.sh;
}
