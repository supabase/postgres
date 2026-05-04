{
  pkgs,
  lib,
  docker-image-ubuntu,
}:
let
  tools = [ pkgs.ansible ];
in
pkgs.dockerTools.buildLayeredImage {
  name = "supabase/ansible-test";
  tag = "latest";
  maxLayers = 30;
  fromImage = docker-image-ubuntu;
  compressor = "zstd";
  config = {
    Env = [
      "PATH=${lib.makeBinPath tools}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    ];
    Cmd = [ "/lib/systemd/systemd" ];
  };
}
