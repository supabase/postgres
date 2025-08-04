{
  pkgs,
  lib,
}:
let
  ubuntu-cloudimg =
    let
      cloudImg = builtins.fetchurl {
        url = "http://cloud-images-archive.ubuntu.com/releases/noble/release-20250430/ubuntu-24.04-server-cloudimg-amd64-root.tar.xz";
        sha256 = "sha256:0rfi3qqs0sqarixfic7pzjpx7d4vldv2d98c5zjv7b90mirznvf9";
      };
    in
    pkgs.runCommand "ubuntu-cloudimg" { nativeBuildInputs = [ pkgs.xz ]; } ''
      mkdir -p $out
      tar --exclude='dev/*' \
          --exclude='etc/systemd/system/network-online.target.wants/systemd-networkd-wait-online.service' \
          --exclude='etc/systemd/system/multi-user.target.wants/systemd-resolved.service' \
          --exclude='usr/lib/systemd/system/tpm-udev.service' \
          --exclude='usr/lib/systemd/system/systemd-remount-fs.service' \
          --exclude='usr/lib/systemd/system/systemd-resolved.service' \
          --exclude='var/lib/apt/lists/*' \
          -xJf ${cloudImg} -C $out
      rm $out/bin $out/lib $out/lib64 $out/sbin
      mkdir -p $out/run/systemd && echo 'docker' > $out/run/systemd/container
      mkdir $out/var/lib/apt/lists/partial
    '';

  dockerImageUbuntu = pkgs.dockerTools.buildImage {
    name = "ubuntu-cloudimg";
    tag = "0.1";
    created = "now";
    extraCommands = ''
      ln -s usr/bin
      ln -s usr/lib
      ln -s usr/lib64
      ln -s usr/sbin
    '';
    copyToRoot = pkgs.buildEnv {
      name = "image-root";
      pathsToLink = [ "/" ];
      paths = [ ubuntu-cloudimg ];
    };
    config.Cmd = [ "/lib/systemd/systemd" ];
  };

  dockerImageUbuntuWithTools =
    let
      tools = [ pkgs.ansible ];
    in
    pkgs.dockerTools.buildLayeredImage {
      name = "ubuntu-cloudimg-with-tools";
      tag = "0.1";
      created = "now";
      maxLayers = 30;
      fromImage = dockerImageUbuntu;
      config = {
        Env = [
          "PATH=${lib.makeBinPath tools}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
        ];
        Cmd = [ "/lib/systemd/systemd" ];
      };
    };
in
pkgs.writeShellApplication {
  name = "ansible-test";
  runtimeInputs = with pkgs; [
    (python3.withPackages (
      ps: with ps; [
        requests
        pytest
        pytest-testinfra
        rich
      ]
    ))
  ];
  text = ''
    echo "Running Ansible tests..."
    export DOCKER_IMAGE=${dockerImageUbuntuWithTools.imageName}:${dockerImageUbuntuWithTools.imageTag}
    if ! docker image inspect $DOCKER_IMAGE > /dev/null; then
      echo "Loading Docker image..."
      docker load < ${dockerImageUbuntuWithTools}
    fi
    ANSIBLE_DIR=${../../ansible}
    pytest -p no:cacheprovider -s -v "$@" $ANSIBLE_DIR/tests --ansible-dir=$ANSIBLE_DIR --docker-image=$DOCKER_IMAGE
  '';
  meta = with pkgs.lib; {
    description = "Ansible test runner";
    platforms = platforms.linux;
  };
}
