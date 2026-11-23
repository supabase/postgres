{
  inputs,
  self,
  coreutils,
  gawk,
  gnugrep,
  openssh,
  stdenv,
  writeShellApplication,
}:
writeShellApplication {
  name = "setup-darwin-linux-builder";
  runtimeInputs = [
    coreutils
    gawk
    gnugrep
    openssh
    inputs.nix-darwin.packages.${stdenv.hostPlatform.system}.darwin-rebuild
  ];
  text = ''
    set -euo pipefail

    if [[ $EUID -ne 0 ]]; then
      echo "Run with sudo: sudo nix run .#setup-darwin-linux-builder" >&2
      exit 1
    fi

    BOOTSTRAP_PID=""
    stop_bootstrap() {
      if [[ -n "$BOOTSTRAP_PID" ]]; then
        kill -- "-$BOOTSTRAP_PID" 2>/dev/null || true
        wait "$BOOTSTRAP_PID" 2>/dev/null || true
        BOOTSTRAP_PID=""
      fi
    }
    trap stop_bootstrap EXIT

    if ! grep -qs aarch64-linux /etc/nix/machines; then
      echo "No Linux builder found. Bootstrapping with the official builder..."
      echo ""
      workdir=$(mktemp -d)
      cd "$workdir"
      set -m
      nix run github:NixOS/nixpkgs/nixos-26.05#darwin.linux-builder \
        >"$workdir/builder.log" 2>&1 </dev/null &
      BOOTSTRAP_PID=$!
      set +m

      hostkey=""
      for _ in $(seq 1 300); do
        hostkey=$(ssh-keyscan -t ed25519 -p 31022 127.0.0.1 2>/dev/null |
          awk '!/^#/ {printf "%s %s", $2, $3}' | base64 | tr -d '\n') || true
        [[ -n "$hostkey" && -f "$workdir/keys/builder_ed25519" ]] && break
        hostkey=""
        sleep 1
      done
      if [[ -z "$hostkey" ]]; then
        echo "Official builder did not start. Log: $workdir/builder.log" >&2
        exit 1
      fi

      echo "Building the configuration on the official builder..."
      NIX_SSHOPTS="-p 31022" nix build \
        "${self}#darwinConfigurations.darwin-nixostest.system" --no-link \
        --builders "ssh-ng://builder@127.0.0.1 aarch64-linux $workdir/keys/builder_ed25519 4 1 kvm,benchmark,big-parallel,nixos-test - $hostkey"
      stop_bootstrap
      cd /
      echo ""
    fi

    echo "Configuring nix-darwin linux-builder..."
    echo ""

    # Backup files that nix-darwin will manage
    echo "Preparing for nix-darwin..."
    for file in /etc/nix/nix.conf /etc/bashrc /etc/zshrc; do
      if [[ -f "$file" && ! -L "$file" ]]; then
        echo "  Backing up $file"
        mv "$file" "$file.before-nix-darwin"
      fi
    done
    echo ""

    revert() {
      for file in /etc/nix/nix.conf /etc/bashrc /etc/zshrc; do
        if [[ ! -L "$file" && -f "$file.before-nix-darwin" ]]; then
          echo "  Restoring original $file"
          mv "$file.before-nix-darwin" "$file"
        fi
      done
    }
    trap 'stop_bootstrap; revert' ERR SIGINT SIGTERM

    echo "This will configure your system with:"
    echo "  - NixOS linux-builder VM (ephemeral)"
    echo "  - 8 cores, 24GB RAM, 100GB disk"
    echo "  - Support for x86_64-linux and aarch64-linux builds"
    echo ""
    echo "Running darwin-rebuild switch..."
    echo ""

    darwin-rebuild switch --refresh --flake ${self}#darwin-nixostest

    echo ""
    echo "Configuration complete!"
    echo ""

    echo "Running verification..."
    echo ""
    if nix run ${self}#verify-darwin-linux-builder; then
      echo ""
      echo "Setup and verification successful!"
    else
      echo ""
      echo "Setup completed but verification found issues."
      echo "Review the failures above and try:"
      echo "  nix run .#verify-darwin-linux-builder"
      echo ""
      echo "to re-run verification after addressing any issues."
      exit 1
    fi

    echo ""
    echo "To control the linux builder vm, you can use:"
    echo "  stop-linux-builder   # stop the linux builder vm"
    echo "  start-linux-builder  # start the linux builder vm"
    echo "  verify-darwin-linux-builder # verify the setup is working"
    echo ""
    echo "If this is the first install, you may need to restart your shell to use these scripts."
  '';
}
