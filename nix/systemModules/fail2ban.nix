{
  lib,
  nixosModulesPath,
  config,
  pkgs,
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
    services.fail2ban = {
      enable = true;
      bantime = "3600";
      packageFirewall = pkgs.nftables;
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
    };

    environment.etc = {
      "fail2ban/filter.d/postgresql.conf".source = ./postgresql-filter.conf;
      "fail2ban/filter.d/pgbouncer.conf".source = ./pgbouncer.conf;
    };

    systemd.services.fail2ban = {
      wantedBy = lib.mkForce [
        "system-manager.target"
      ];
    };
  };
}
