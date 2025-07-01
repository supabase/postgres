{ ... }:
{
  perSystem =
    {
      pkgs,
      self',
      config,
      ...
    }:
    let
      # Define pythonEnv here
      pythonEnv = pkgs.python3.withPackages (
        ps: with ps; [
          boto3
          docker
          pytest
          pytest-testinfra
          requests
          ec2instanceconnectcli
          paramiko
        ]
      );
      mkCargoPgrxDevShell =
        { pgrxVersion, rustVersion }:
        pkgs.mkShell {
          packages = with pkgs; [
            self'.packages."cargo-pgrx_${pgrxVersion}"
            (rust-bin.stable.${rustVersion}.default.override { extensions = [ "rust-src" ]; })
          ];
          shellHook = ''
            export HISTFILE=.history
          '';
        };
    in
    {
      devShells = {
        default = pkgs.mkShell {
          packages =
            with pkgs;
            [
              coreutils
              just
              nix-update
              #pg_prove
              shellcheck
              ansible
              ansible-lint
              (packer.overrideAttrs (_oldAttrs: {
                version = "1.7.8";
              }))

              self'.packages.start-server
              self'.packages.start-client
              self'.packages.start-replica
              self'.packages.migrate-tool
              self'.packages.sync-exts-versions
              self'.packages.build-test-ami
              self'.packages.run-testinfra
              self'.packages.cleanup-ami
              dbmate
              nushell
              pythonEnv
              config.treefmt.build.wrapper
            ]
            ++ self'.packages.docs.nativeBuildInputs;
          shellHook = ''
            export HISTFILE=.history
            ${config.pre-commit.installationScript}
          '';
        };
        cargo-pgrx_0_11_3 = mkCargoPgrxDevShell {
          pgrxVersion = "0_11_3";
          rustVersion = "1.80.0";
        };
        cargo-pgrx_0_12_6 = mkCargoPgrxDevShell {
          pgrxVersion = "0_12_6";
          rustVersion = "1.80.0";
        };
      };
    };
}
