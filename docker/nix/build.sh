#!/bin/env bash
set -eou pipefail

nix --version
cd /workspace
nix build .#psql_15/bin -o psql_15
nix build .#psql_15/docker -o psql_15_docker
nix build .#psql_15/docker.copyToRegistry 
