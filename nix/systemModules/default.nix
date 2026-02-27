{
  ...
}:
{
  imports = [ ./tests ];
  flake = {
    systemModules = {
      ssh-config = {
        environment.etc."ssh/sshd_config.d/local.conf" = {
          text = ''
            Match Address 127.0.0.1,::1
              ForceCommand /bin/false
              DisableForwarding yes
              PermitTunnel no
          '';
          user = "root";
          group = "root";
          mode = "0644";
        };
      };
    };
  };
}
