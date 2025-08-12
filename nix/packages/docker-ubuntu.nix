{
  runCommand,
  dockerTools,
  xz,
  buildEnv,
}:
let
  ubuntu-cloudimg =
    let
      cloudImg = builtins.fetchurl {
        url = "http://cloud-images-archive.ubuntu.com/releases/noble/release-20250430/ubuntu-24.04-server-cloudimg-amd64-root.tar.xz";
        sha256 = "sha256:0rfi3qqs0sqarixfic7pzjpx7d4vldv2d98c5zjv7b90mirznvf9";
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
      rm $out/bin $out/lib $out/lib64 $out/sbin
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
