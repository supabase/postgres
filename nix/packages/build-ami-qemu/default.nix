{
  cdrkit,
  coreutils,
  fetchurl,
  findutils,
  gitMinimal,
  gnugrep,
  gnused,
  qemu,
  writeShellApplication,
  yq,
}:
writeShellApplication {
  name = "build-ami-qemu";

  runtimeInputs = [
    cdrkit
    coreutils
    findutils
    gitMinimal
    gnugrep
    gnused
    qemu
    yq
  ];

  runtimeEnv = {
    CLOUDIMG = fetchurl {
      url = "https://cloud-images.ubuntu.com/releases/noble/release-20260926/ubuntu-24.04-server-cloudimg-arm64.img";
      sha256 = "1d6bffe64b848468ac97f821d369a4846d983de1800ccf6b5ec8853e85cefc55";
    };
    CODE = "${qemu}/share/qemu/edk2-aarch64-code.fd";
    VARS = "${qemu}/share/qemu/edk2-arm-vars.fd";
  };

  text = builtins.readFile ./build-ami-qemu.sh;

  meta.platforms = [
    "aarch64-darwin"
    "aarch64-linux"
  ];
}
