#!/usr/bin/env bash
set -euo pipefail

arch=${1:?usage: presign-supa-tripwire.sh <amd64|arm64>}
version=$(nix run --inputs-from . nixpkgs#yq -- -er .supa_tripwire_release ansible/vars.yml)

nix run --inputs-from . nixpkgs#awscli2 -- s3 presign --region ap-southeast-1 --expires-in 3600 "s3://supabase-internal-artifacts/supa-tripwire/supa-tripwire-v$version-$arch.tar.xz"
