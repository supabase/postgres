#!/bin/env bash
set -eou pipefail

nix --version
cd /workspace
nix build .#psql_15/bin -o psql_15
nix build .#psql_15/docker
nix flake check -L --all-systems
nix copy --to s3://nix-postgres-artifacts?secret-key=nix-secret-key ./psql_15
AUTH_FILE=$(mktemp)
python3 -c "
import json
import base64
import os

auth = base64.b64encode(f'{os.environ['DOCKER_USERNAME']}:{os.environ['DOCKER_PASSWORD']}'.encode()).decode()
config = {
    'auths': {
        'docker.io': {
            'auth': auth
        }
    }
}
with open('$AUTH_FILE', 'w') as f:
    json.dump(config, f)
" 2>/dev/null

export REGISTRY_AUTH_FILE="$AUTH_FILE"

# Run the copyToRegistry 
nix run .#psql_15/docker.copyToRegistry

# Clean up the temporary file
rm "$AUTH_FILE"