#!/bin/env bash
set -eou pipefail
echo "$REGISTRY"
nix --version
cd /workspace
nix build .#psql_15/bin -o psql_15
nix build .#psql_15/docker #just to test the build
nix run .#psql_15/docker.copyToRegistry 
