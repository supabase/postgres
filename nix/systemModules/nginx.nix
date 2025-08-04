{ ... }:
{ config, ... }:
{
  config = {
    system-manager.preActivationAssertions = {
      waitForSystemd = {
        enable = true;
        script = ''
          TIMEOUT=20
          while ! systemctl is-system-running --quiet; do
            if [ $TIMEOUT -le 0 ]; then
              echo "Systemd did not start in time."
              exit 1
            fi
            sleep 0.1;
            echo "Waiting for systemd to start..."
            TIMEOUT=$((TIMEOUT - 1))
          done
        '';
      };
    };

    services.nginx.enable = true;
  };
}
