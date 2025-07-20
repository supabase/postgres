@echo off
wsl bash -c "source ~/.nix-profile/etc/profile.d/nix.sh && exec nix --extra-experimental-features 'nix-command flakes' run nixpkgs#nixd"