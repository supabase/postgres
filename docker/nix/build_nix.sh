#!/bin/env bash
set -eou pipefail

nix --version
if [ -d "/workspace" ]; then
    cd /workspace
fi

nix run "github:Mic92/nix-fast-build?rev=b1dae483ab7d4139a6297e02b6de9e5d30e43d48" -- --skip-cached --no-nom --flake ".#checks"
