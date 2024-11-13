#!/bin/env bash
set -eou pipefail

nix --version
if [ -d "/workspace" ]; then
    cd /workspace
fi
if [ $(nix-instantiate --eval -E builtins.currentSystem | tr -d '"') == "x86_64-darwin" ]; then
    nix build .#checks.$(nix-instantiate --eval -E builtins.currentSystem | tr -d '"').psql_15 -L --no-link
    nix build .#psql_15/bin -o psql_15
    nix copy --to s3://nix-postgres-artifacts?secret-key=nix-secret-key ./psql_15
else
    nix build .#checks.$(nix-instantiate --eval -E builtins.currentSystem | tr -d '"').psql_15 -L --no-link
    nix build .#checks.$(nix-instantiate --eval -E builtins.currentSystem | tr -d '"').psql_16 -L --no-link
    nix build .#psql_15/bin -o psql_15
    nix build .#psql_16/bin -o psql_16
    nix copy --to s3://nix-postgres-artifacts?secret-key=nix-secret-key ./psql_15
    nix copy --to s3://nix-postgres-artifacts?secret-key=nix-secret-key ./psql_16
fi
