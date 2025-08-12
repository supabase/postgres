{ self, ... }:
{
  perSystem =
    {
      lib,
      pkgs,
      self',
      ...
    }:
    {
      packages = lib.optionalAttrs (pkgs.stdenv.hostPlatform.isLinux) {
        check-system-manager =
          let
            lib = pkgs.lib;
            systemManagerConfig = self.systemConfigs.${pkgs.system}.default;

            dockerImageUbuntuWithTools =
              let
                tools = [ systemManagerConfig ];
              in
              pkgs.dockerTools.buildLayeredImage {
                name = "ubuntu-cloudimg-with-tools";
                tag = "0.2";
                created = "now";
                maxLayers = 30;
                fromImage = self'.packages.docker-image-ubuntu;
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
            name = "system-manager-test";
            passthru = {
              inherit systemManagerConfig dockerImageUbuntuWithTools;
            };
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
              export DOCKER_IMAGE=${dockerImageUbuntuWithTools.imageName}:${dockerImageUbuntuWithTools.imageTag}
              TEST_DIR=${./.}
              pytest -p no:cacheprovider -s -v "$@" $TEST_DIR --image-name=$DOCKER_IMAGE --image-path=${dockerImageUbuntuWithTools}
            '';
            meta = with pkgs.lib; {
              description = "Test deployment with system-manager";
              platforms = platforms.linux;
            };
          };
      };
    };
}
