#!/bin/env bash
set -eou pipefail

nix --version
if [ -d "/workspace" ]; then
    cd /workspace
fi

SYSTEM=$(nix-instantiate --eval -E builtins.currentSystem | tr -d '"')

nix build .#checks.$SYSTEM.psql_15 -L --no-link
nix build .#checks.$SYSTEM.psql_orioledb-17 -L --no-link
nix build .#checks.$SYSTEM.psql_17 -L --no-link
nix build .#psql_15/bin -o psql_15 -L
nix build .#psql_orioledb-17/bin -o psql_orioledb_17 -L
nix build .#psql_17/bin -o psql_17 -L
nix build .#wal-g-2 -o wal-g-2 -L
nix build .#wal-g-3 -o wal-g-3 -L

# Copy to S3
if [[ -n "${AWS_ACCESS_KEY_ID-}" && -n "${AWS_SECRET_ACCESS_KEY-}" ]]; then
    nix copy --to s3://nix-postgres-artifacts?secret-key=nix-secret-key ./wal-g-2
    nix copy --to s3://nix-postgres-artifacts?secret-key=nix-secret-key ./wal-g-3
    nix copy --to s3://nix-postgres-artifacts?secret-key=nix-secret-key ./psql_15
    nix copy --to s3://nix-postgres-artifacts?secret-key=nix-secret-key ./psql_orioledb_17
    nix copy --to s3://nix-postgres-artifacts?secret-key=nix-secret-key ./psql_17
fi

if [ "$SYSTEM" = "aarch64-linux" ]; then
    nix build .#postgresql_15_debug -o ./postgresql_15_debug
    nix build .#postgresql_15_src -o ./postgresql_15_src
    nix build .#postgresql_orioledb-17_debug -o ./postgresql_orioledb-17_debug
    nix build .#postgresql_orioledb-17_src -o ./postgresql_orioledb-17_src
    nix build .#postgresql_17_debug -o ./postgresql_17_debug
    nix build .#postgresql_17_src -o ./postgresql_17_src

    if [[ -n "${AWS_ACCESS_KEY_ID-}" && -n "${AWS_SECRET_ACCESS_KEY-}" ]]; then
        nix copy --to s3://nix-postgres-artifacts?secret-key=nix-secret-key ./postgresql_15_debug-debug
        nix copy --to s3://nix-postgres-artifacts?secret-key=nix-secret-key  ./postgresql_15_src
        nix copy --to s3://nix-postgres-artifacts?secret-key=nix-secret-key ./postgresql_orioledb-17_debug-debug
        nix copy --to s3://nix-postgres-artifacts?secret-key=nix-secret-key  ./postgresql_orioledb-17_src
        nix copy --to s3://nix-postgres-artifacts?secret-key=nix-secret-key ./postgresql_17_debug-debug
        nix copy --to s3://nix-postgres-artifacts?secret-key=nix-secret-key  ./postgresql_17_src
    fi
fi
