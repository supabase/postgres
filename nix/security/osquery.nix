{ pkgs, ... }:
{
  environment.systemPackages = [ pkgs.osquery ];

  environment.etc."osquery/osquery.conf" = {
    text = builtins.toJSON {
      options = {
        config_plugin = "filesystem";
        logger_plugin = "filesystem";
        logger_path = "/var/log/osquery";
        disable_logging = false;
        schedule_splay_percent = 10;
        pidfile = "/var/run/osquery/osqueryd.pidfile";
        events_expiry = 3600;
        database_path = "/var/osquery/osquery.db";
        verbose = false;
        worker_threads = 2;
        watchdog_memory_limit = 50;
        watchdog_utilization_limit = 5;
      };
      schedule = {
        listening_ports = {
          query = "SELECT pid, port, protocol, address, name FROM listening_ports WHERE port NOT IN (5432, 6543, 8000, 3000);";
          interval = 300;
          description = "Listening ports excluding known Supabase services";
        };
        unexpected_processes = {
          query = "SELECT pid, name, path, cmdline, uid FROM processes WHERE uid = 0 AND path NOT LIKE '/usr/lib/postgresql%' AND path NOT LIKE '/opt/supabase%' AND path NOT LIKE '/usr/sbin/%' AND path NOT LIKE '/nix/store%';";
          interval = 120;
          description = "Root processes with unexpected binary paths";
        };
        authorized_keys = {
          query = "SELECT * FROM authorized_keys;";
          interval = 3600;
          description = "SSH authorized keys inventory";
        };
        crontab = {
          query = "SELECT * FROM crontab;";
          interval = 600;
          description = "Scheduled cron jobs";
        };
        kernel_modules = {
          query = "SELECT name, size, status, address FROM kernel_modules;";
          interval = 3600;
          description = "Loaded kernel modules";
        };
        system_info = {
          query = "SELECT hostname, cpu_brand, physical_memory, hardware_vendor, hardware_model FROM system_info;";
          interval = 3600;
          description = "System hardware and OS information";
        };
      };
    };
    mode = "0644";
  };

  systemd.services.osqueryd = {
    enable = true;
    description = "osquery daemon";
    after = [ "network.target" "syslog.target" ];
    wantedBy = [ "system-manager.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p /var/log/osquery /var/osquery /var/run/osquery";
      ExecStart = "${pkgs.osquery}/bin/osqueryd --config_path /etc/osquery/osquery.conf --pidfile /var/run/osquery/osqueryd.pidfile --database_path /var/osquery/osquery.db";
      Restart = "on-failure";
      RestartSec = 10;
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/log/osquery 0755 root root -"
    "d /var/osquery 0755 root root -"
    "d /var/run/osquery 0755 root root -"
  ];
}
