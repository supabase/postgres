#!/bin/env bash
set -eou pipefail

nix --version
if [ -d "/workspace" ]; then
    cd /workspace
fi
nix build .#psql_15/bin -o psql_15
nix flake check -L 
nix copy --to s3://nix-postgres-artifacts?secret-key=nix-secret-key ./psql_15
