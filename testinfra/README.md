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
# docker must be running

# build extensions & pg binaries
mkdir -p /tmp/extensions ansible/files/extensions
docker buildx build \
  $(yq 'to_entries | map(select(.value|type == "!!str")) |  map(" --build-arg " + .key + "=" + .value) | join("")' 'ansible/vars.yml') \
  --target=extensions \
  --tag=supabase/postgres:extensions \
  --platform=linux/arm64 \
  --output=type=tar,dest=- \
  . | tar xv -C ansible/files/extensions --strip-components 1

mkdir -p /tmp/build ansible/files/postgres
docker buildx build \
  --build-arg ubuntu_release=noble \
  --build-arg ubuntu_release_no=24.04 \
  --build-arg postgresql_major=16 \
  --build-arg postgresql_release=16.2 \
  --build-arg CPPFLAGS=-mcpu=neoverse-n1 \
  --file=docker/Dockerfile \
  --target=pg-deb \
  --tag=supabase/postgres:deb \
  --platform=linux/arm64 \
  --output=type=tar,dest=- \
  . | tar xv -C ansible/files/postgres --strip-components 1

# build AMI
AWS_PROFILE=supabase-dev packer build \
  -var-file=development-arm.vars.pkr.hcl \
  -var-file=common.vars.pkr.hcl \
  -var "ansible_arguments=" \
  -var "postgres-version=ci-ami-test" \
  -var "region=ap-southeast-1" \
  -var 'ami_regions=["ap-southeast-1"]' \
  -var "force-deregister=true" \
  amazon-arm64.pkr.hcl

# run tests
AWS_PROFILE=supabase-dev pytest -vv -s testinfra/test_*.py
```
