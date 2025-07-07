{ withSystem }:
{ config, pkgs, ... }:
{
  config = {
    nixpkgs.hostPlatform = "x86_64-linux";

    system-manager.allowAnyDistro = true;

    systemd.tmpfiles.rules = [ "d '/etc/postgresql-custom' 0750 root root - -" ];
    environment = {

      etc = {
        "postgresql-custom/read-replica.conf".source = ../../ansible/files/postgresql_config/custom_read_replica.conf.j2;
      };
      systemPackages = with pkgs; [
        glibcLocales
        nix-info
      ];
    };
  };
}
