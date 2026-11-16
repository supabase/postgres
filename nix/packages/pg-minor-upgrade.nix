{
  perSystem =
    { lib, pkgs, ... }:
    let
      scripts = ../../ansible/files/admin_api_scripts/pg_upgrade_scripts;
      # systemctl and nix come from the host.
      script = pkgs.writeShellApplication {
        name = "pg-minor-upgrade";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.gawk
          pkgs.util-linux
        ];
        runtimeEnv.PG_UPGRADE_COMMON = "${scripts + "/common.sh"}";
        text = builtins.readFile (scripts + "/minor.sh");
      };
      unit = pkgs.writeTextDir "lib/systemd/system/pg-minor-upgrade@.service" ''
        [Unit]
        Description=In-place Postgres minor upgrade to %f

        [Service]
        Type=oneshot
        EnvironmentFile=-/etc/default/pg-minor-upgrade
        ExecStart=${lib.getExe' pkgs.util-linux "flock"} -n /run/lock/pg-minor-upgrade.lock ${lib.getExe script} %f
        TimeoutStartSec=15min
      '';
      pg-minor-upgrade = pkgs.symlinkJoin {
        name = "pg-minor-upgrade";
        paths = [
          script
          unit
        ];
      };
    in
    {
      packages = { inherit pg-minor-upgrade; };
      legacyPackages = { inherit pg-minor-upgrade; };
    };
}
