# Download nix store paths with timeout and retry.
{
  perSystem =
    { pkgs, ... }:
    {
      packages.nix-dl = pkgs.writeShellApplication {
        name = "nix-dl";
        runtimeInputs = [ pkgs.coreutils ];
        text = ''
          # nix-store -r can hang indefinitely: https://github.com/NixOS/nix/issues/2560
          timeout_="''${NIX_DL_TIMEOUT:-120s}"
          kill_grace="''${NIX_DL_KILL_GRACE:-10s}"
          attempts="''${NIX_DL_ATTEMPTS:-3}"

          for path in "$@"; do
            ok="false"
            for attempt in $(seq 1 "$attempts"); do
              if timeout -k "$kill_grace" "$timeout_" nix-store -r "$path" >/dev/null; then
                ok="true"
                break
              fi
              if [ "$attempt" -lt "$attempts" ]; then
                echo "WARNING: nix-store -r attempt $attempt/$attempts for $path failed or stalled (>=$timeout_ + up to $kill_grace kill grace); retrying" >&2
              else
                echo "ERROR: nix-store -r failed after $attempts attempts for $path" >&2
              fi
            done
            [ "$ok" = "true" ] || exit 1
          done
        '';
      };
    };
}
