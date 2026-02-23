{
  lib,
  nixosModulesPath,
  config,
  ...
}:
let
  cfg = config.supabase.services.fail2ban;
in
{
  imports = [
    "${nixosModulesPath}/services/security/fail2ban.nix"
  ];

  options = {
    # Create a dummy openssh option to unbreak the
    # > The option `services.openssh.settings' does not exist.
    # we face when importing the NixOS fail2ban.nix module.
    #
    # Note: the fail2ban module is trying to increase the log
    # verbosity of the openssh daemon to simplify debug. We don't
    # really need this feature: system-manager is not controlling the
    # ssh daemon here.
    #
    # TOREMOVE if we end up provisionning openssh through
    # systemmanager.
    services.openssh.settings = lib.mkOption {
      type = lib.types.attrs;
    };
    # Some goes for nftables
    networking.nftables.enable = lib.mkEnableOption "dummy nftable module";

    # TODO move to iptables
    supabase.services.fail2ban = {
      enable = lib.mkEnableOption "Fail2Ban";
    };
  };

  config = lib.mkIf cfg.enable {
    # Dummy
    networking.nftables.enable = true;
    # TODO: (last bit form Ansible task)
    # - name: Configure journald
    #   copy:
    #     src: files/fail2ban_config/jail-ssh.conf
    #     dest: /etc/fail2ban/jail.d/sshd.local
    #   when: debpkg_mode or nixpkg_mode
    services.fail2ban = {
      enable = true; # TODO: don't use nixpkgs fail2ban
      bantime = "3600";
      jails = {
        postgresql = {
          settings = {
            enabled = true;
            port = "5432";
            protocol = "tcp";
            filter = "postgresql";
            logpath = "/var/log/postgresql/auth-failures.csv";
            maxretry = 3;
            ignoreip = "192.168.0.0/16 172.17.1.0/20";
          };
        };
        pgbouncer = {
          settings = {
            enabled = true;
            port = "6543";
            protocol = "tcp";
            filter = "pgbouncer";
            backend = "systemd[journalflags=1]";
            maxretry = 3;
          };
        };
      };
      # TODO: extraPackages = [ pkgs.nftables ];
    };

    environment.etc = {
      "fail2ban/filter.d/postgresql.conf".text = ''
        [Definition]
        failregex = ^.*,.*,.*,.*,"<HOST>:.*password authentication failed for user.*$
        ignoreregex = ^.*,.*,.*,.*,"127\.0\.0\.1.*password authentication failed for user.*$
                      ^.*,.*,.*,.*,"<HOST>:.*password authentication failed for user ""supabase_admin".*$
                      ^.*,.*,.*,.*,"<HOST>:.*password authentication failed for user ""supabase_auth_admin".*$
                      ^.*,.*,.*,.*,"<HOST>:.*password authentication failed for user ""supabase_storage_admin".*$
                      ^.*,.*,.*,.*,"<HOST>:.*password authentication failed for user ""authenticator".*$
                      ^.*,.*,.*,.*,"<HOST>:.*password authentication failed for user ""pgbouncer".*$
      '';

      "fail2ban/filter.d/pgbouncer.conf".text = ''
        [Definition]
        failregex = ^.+@<HOST>:.+password authentication failed$
        journalmatch = _SYSTEMD_UNIT=pgbouncer.service
      '';
    };

    systemd.services.fail2ban = {
      wantedBy = lib.mkForce [
        "system-manager.target"
      ];
      # TODO:
      # after = [ "nftables.service" ];
      # wants = [ "nftables.service" ];
    };
  };
}
