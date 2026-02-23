{ pkgs, ... }:
let
  policyDir = ./policies;
in
{
  environment.systemPackages = [ pkgs.tetragon ];

  environment.etc."tetragon/tetragon.yaml" = {
    text = builtins.toJSON {
      export-filename = "/var/log/tetragon/events.log";
      export-rate-limit = 100;
      export-file-max-size-mb = 10;
      export-file-max-backups = 5;
      tracing-policy-dir = "/etc/tetragon/tetragon.tp.d";
    };
    mode = "0644";
  };

  environment.etc."tetragon/tetragon.tp.d/unexpected-exec.yaml" = {
    source = "${policyDir}/unexpected-exec.yaml";
    mode = "0644";
  };

  environment.etc."tetragon/tetragon.tp.d/sensitive-writes.yaml" = {
    source = "${policyDir}/sensitive-writes.yaml";
    mode = "0644";
  };

  environment.etc."tetragon/tetragon.tp.d/network-monitor.yaml" = {
    source = "${policyDir}/network-monitor.yaml";
    mode = "0644";
  };

  environment.etc."tetragon/tetragon.tp.d/privilege-escalation.yaml" = {
    source = "${policyDir}/privilege-escalation.yaml";
    mode = "0644";
  };

  systemd.services.tetragon = {
    enable = true;
    description = "Tetragon eBPF security observability";
    after = [ "network.target" ];
    wantedBy = [ "system-manager.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.tetragon}/bin/tetragon --config-file /etc/tetragon/tetragon.yaml";
      Restart = "on-failure";
      RestartSec = 10;
      MemoryMax = "100M";
      CPUQuota = "5%";
      AmbientCapabilities = "CAP_SYS_ADMIN CAP_BPF CAP_PERFMON";
      CapabilityBoundingSet = "CAP_SYS_ADMIN CAP_BPF CAP_PERFMON";
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/log/tetragon 0755 root root -"
  ];
}
