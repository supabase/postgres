{
  pkgs,
  lib,
  docker-image-ubuntu,
}:
let
  dockerImageUbuntuWithTools =
    let
      tools = [ pkgs.ansible ];
    in
    pkgs.dockerTools.buildLayeredImage {
      name = "ubuntu-cloudimg-with-tools";
      tag = "0.1";
      created = "now";
      maxLayers = 30;
      fromImage = docker-image-ubuntu;
      compressor = "zstd";
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
        pytest-xdist
        rich
      ]
    ))
  ];
  text = ''
    echo "Running Ansible tests..."
    export DOCKER_IMAGE=${dockerImageUbuntuWithTools.imageName}:${dockerImageUbuntuWithTools.imageTag}
    echo "Loading Docker image..."
    docker load < ${dockerImageUbuntuWithTools}
    FLAKE_DIR=${../..}
    pytest -x -p no:cacheprovider -s -v "$@" $FLAKE_DIR/ansible/tests --flake-dir=$FLAKE_DIR --docker-image=$DOCKER_IMAGE
  '';
  meta = with pkgs.lib; {
    description = "Ansible test runner";
    platforms = platforms.linux;
  };
}
