{
  perSystem =
    { lib, pkgs, ... }:
    let
      scripts = ../../ansible/files/admin_api_scripts/pg_upgrade_scripts;
      # Appended, so host tools come first. The host provides systemctl and nix.
      fallbackPath = lib.makeBinPath [
        pkgs.coreutils
        pkgs.gawk
        pkgs.util-linux
      ];
      pg-minor-upgrade = pkgs.stdenvNoCC.mkDerivation {
        name = "pg-minor-upgrade";
        dontUnpack = true;
        nativeBuildInputs = [ pkgs.makeWrapper ];
        installPhase = ''
          install -Dm755 ${scripts}/minor.sh $out/libexec/pg-minor-upgrade/minor.sh
          install -Dm644 ${scripts}/common.sh $out/libexec/pg-minor-upgrade/common.sh
          makeWrapper $out/libexec/pg-minor-upgrade/minor.sh $out/bin/pg-minor-upgrade \
            --suffix PATH : /usr/lib/postgresql/bin:${fallbackPath}

          install -Dm644 /dev/stdin $out/lib/systemd/system/pg-minor-upgrade@.service <<EOF
          [Unit]
          Description=In-place Postgres minor upgrade to %f

          [Service]
          Type=oneshot
          EnvironmentFile=-/etc/default/pg-minor-upgrade
          ExecStart=${pkgs.util-linux}/bin/flock -n /run/lock/pg-minor-upgrade.lock $out/bin/pg-minor-upgrade %f
          TimeoutStartSec=15min
          EOF
        '';
      };
    in
    {
      packages = { inherit pg-minor-upgrade; };
      legacyPackages = { inherit pg-minor-upgrade; };
    };
}
