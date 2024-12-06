#!/bin/env bash
set -eou pipefail

nix --version
if [ -d "/workspace" ]; then
    cd /workspace
fi
SYSTEM=$(nix-instantiate --eval -E builtins.currentSystem | tr -d '"')
nix build .#psql_15/bin -o psql_15
nix flake check -L 
nix copy --to s3://nix-postgres-artifacts?secret-key=nix-secret-key ./psql_15
if [ "$SYSTEM" = "aarch64-linux" ]; then
    nix build .#postgresql_15_debug -o ./postgresql_15_debug
    nix build .#postgresql_15_src -o ./postgresql_15_src
    nix copy --to s3://nix-postgres-artifacts?secret-key=nix-secret-key ./postgresql_15_debug-debug
    nix copy --to s3://nix-postgres-artifacts?secret-key=nix-secret-key  ./postgresql_15_src
fi
