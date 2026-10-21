# Testinfra Integration Tests

## Prerequisites

- Docker
- Packer
- yq
- Python deps:

```sh
pip3 install boto3 boto3-stubs[essential] docker ec2instanceconnectcli pytest pytest-testinfra[paramiko,docker] requests
```

## Running locally

```sh
set -euo pipefail
# cwd: repo root

# build AMI
# The SHA must be pushed to GitHub: stage 2 evaluates packages from github:supabase/postgres/<sha>.
export AWS_PROFILE=supabase-dev AWS_REGION=us-east-1
sha=$(git rev-parse HEAD)
# build-ami writes its outputs (AMI IDs, execution ID) to $GITHUB_OUTPUT when it is set
export GITHUB_OUTPUT=$(mktemp)
nix run .#build-ami -- \
  --arch arm64 \
  --postgres-major-version 17 \
  --git-sha "$sha"

# run tests
export AMI_ID=$(sed -n 's/^stage2_ami_id=//p' "$GITHUB_OUTPUT")
export EXECUTION_ID=$(sed -n 's/^execution_id=//p' "$GITHUB_OUTPUT")
pytest -vv -s testinfra/test_*.py
```
