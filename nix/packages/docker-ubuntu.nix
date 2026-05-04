{
  runCommand,
  dockerTools,
  xz,
  buildEnv,
  stdenv,
}:
let
  ubuntu-cloudimg =
    let

      cloudImg =
        if stdenv.hostPlatform.system == "x86_64-linux" then
          builtins.fetchurl {
            url = "https://cloud-images.ubuntu.com/releases/noble/release-20251026/ubuntu-24.04-server-cloudimg-amd64-root.tar.xz";
            sha256 = "0y3d55f5qy7bxm3mfmnxzpmwp88d7iiszc57z5b9npc6xgwi28np";
          }
        else
          builtins.fetchurl {
            url = "https://cloud-images.ubuntu.com/releases/noble/release-20251026/ubuntu-24.04-server-cloudimg-arm64-root.tar.xz";
            sha256 = "1l4l0llfffspzgnmwhax0fcnjn8ih8n4azhfaghng2hh1xvr4a17";
          };
    in
    runCommand "ubuntu-cloudimg" { nativeBuildInputs = [ xz ]; } ''
      mkdir -p $out
      tar --exclude='dev/*' \
          --exclude='etc/systemd/system/network-online.target.wants/systemd-networkd-wait-online.service' \
          --exclude='etc/systemd/system/multi-user.target.wants/systemd-resolved.service' \
          --exclude='usr/lib/systemd/system/tpm-udev.service' \
          --exclude='usr/lib/systemd/system/systemd-remount-fs.service' \
          --exclude='usr/lib/systemd/system/systemd-resolved.service' \
          --exclude='usr/lib/systemd/system/proc-sys-fs-binfmt_misc.automount' \
          --exclude='usr/lib/systemd/system/sys-kernel-*' \
          --exclude='var/lib/apt/lists/*' \
          -xJf ${cloudImg} -C $out
      rm -f $out/bin $out/lib $out/lib64 $out/sbin
      mkdir -p $out/run/systemd && echo 'docker' > $out/run/systemd/container
      mkdir $out/var/lib/apt/lists/partial
    '';
in
dockerTools.buildImage {
  name = "ubuntu-cloudimg";
  tag = "24.04";
  created = "now";
  extraCommands = ''
    ln -s usr/bin
    ln -s usr/lib
    ln -s usr/lib64
    ln -s usr/sbin
  '';
  copyToRoot = buildEnv {
    name = "image-root";
    pathsToLink = [ "/" ];
    paths = [ ubuntu-cloudimg ];
  };
  config.Cmd = [ "/lib/systemd/systemd" ];
}
