{
  inputs,
  self,
  stdenv,
  writeShellApplication,
}:
writeShellApplication {
  name = "setup-darwin-linux-builder";
  runtimeInputs = [
    inputs.nix-darwin.packages.${stdenv.hostPlatform.system}.darwin-rebuild
  ];
  text = ''
    set -euo pipefail

    echo "Configuring nix-darwin linux-builder..."
    echo ""

    # Backup files that nix-darwin will manage
    echo "Preparing for nix-darwin..."
    for file in /etc/nix/nix.conf /etc/bashrc /etc/zshrc; do
      if [[ -f "$file" && ! -L "$file" ]]; then
        echo "  Backing up $file"
        sudo mv "$file" "$file.before-nix-darwin"
      fi
    done
    echo ""

    revert() {
      for file in /etc/nix/nix.conf /etc/bashrc /etc/zshrc; do
        if [[ ! -L "$file" && -f "$file.before-nix-darwin" ]]; then
          echo "  Restoring original $file"
          sudo mv "$file.before-nix-darwin" "$file"
        fi
      done
    }
    trap revert ERR SIGINT SIGTERM

    echo "This will configure your system with:"
    echo "  - NixOS linux-builder VM (ephemeral)"
    echo "  - 6 cores, 8GB RAM, 40GB disk"
    echo "  - Support for x86_64-linux and aarch64-linux builds"
    echo ""
    echo "Running darwin-rebuild switch..."
    echo ""

    sudo darwin-rebuild switch --refresh --flake ${self}#darwin-nixostest

    echo ""
    echo "Configuration complete!"
    echo ""
    echo "The linux-builder is now configured. You can test it by:"
    echo "  nix build --system x86_64-linux nixpkgs#hello"
    echo "  nix build --system aarch64-linux nixpkgs#hello"
    echo ""
    echo "To control the linux builder vm, you can use:"
    echo "  stop-linux-builder  # to stop the linux builder vm"
    echo "  start-linux-builder # to start the linux builder vm"
    echo ""
    echo "If this is the first install, you may need to restart your shell to use these scripts."
  '';
}
