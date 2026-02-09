{
  lib,
  config,
  ...
}:
let
  cfg = config.supabase.services.logrotate;
in
{
  options = {
    supabase.services.logrotate = {
      enable = lib.mkEnableOption "Whether to enable the logrotate systemd service.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.etc = {
      "logrotate.d/logrotate-postgres-auth.conf" = {
        text = ''
          /var/log/postgresql/auth-failures.csv {
            size 10M
            rotate 5
            compress
            delaycompress
            notifempty
            missingok
          }
        '';
        user = "root";
        group = "root";
        mode = "0644";
      };
      "logrotate.d/logrotate-postgres-csv.conf" = {
        text = ''
          /var/log/postgresql/postgresql.csv {
            size 50M
            rotate 9
            compress
            delaycompress
            notifempty
            missingok
            postrotate
              sudo -u postgres /usr/lib/postgresql/bin/pg_ctl -D /var/lib/postgresql/data logrotate
            endscript
          }
        '';
        user = "root";
        group = "root";
        mode = "0644";
      };
      "logrotate.d/logrotate-postgres.conf" = {
        text = ''
          /var/log/postgresql/postgresql.log {
            size 50M
            rotate 3
            copytruncate
            delaycompress
            compress
            notifempty
            missingok
          }
        '';
        user = "root";
        group = "root";
        mode = "0644";
      };
      "logrotate.d/logrotate-walg.conf" = {
        text = ''
          /var/log/wal-g/*.log {
            size 50M
            rotate 3
            copytruncate
            delaycompress
            compress
            notifempty
            missingok
          }
        '';
        user = "root";
        group = "root";
        mode = "0644";
      };
    };

    systemd.timers.logrotate = {
      wantedBy = [ "timers.target" ];
      timerConfig.OnCalendar = "*:0/5";
      timerConfig.Persistent = true;
    };
  };
}
