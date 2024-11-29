# QEMU artifact

We build a container image that contains a QEMU qcow2 disk image. This container image can be use with KubeVirt's [containerDisk](https://kubevirt.io/user-guide/storage/disks_and_volumes/#containerdisk) functionality to boot up VMs off the qcow2 image.

Container images are a convenient mechanism to ship the disk image to the nodes where they're needed.

Given the size of the image, the first VM using it on a node might take a while to come up, while the image is being pulled down. The image can be pre-fetched to avoid this; we might also switch to other deployment mechanisms in the future.

# Building QEMU artifact

## Creating a bare-metal instance

We launch an Ubuntu 22 bare-metal instance; we're using the `c6g.metal` instance type in this case, but any ARM instance type is sufficient for our purposes. In the example below the region used is: `ap-south-1`.

```bash
# create a security group for your instance
aws ec2 create-security-group --group-name "launch-wizard-1" --description "launch-wizard-1 created 2024-11-26T00:32:56.039Z" --vpc-id "insert-vpc-id"

# using the generated security group ID (insert-sg-group), ensure that it allows for SSH access
aws ec2 authorize-security-group-ingress --group-id "insert-sg-group" --ip-permissions '{"IpProtocol":"tcp","FromPort":22,"ToPort":22,"IpRanges":[{"CidrIp":"0.0.0.0/0"}]}'

# spin up your instance with the generated security group ID (insert-sg-group)
aws ec2 run-instances \
--image-id "ami-0a87daabd88e93b1f" \
--instance-type "c6g.metal" \
--key-name "INSERT_KEY_PAIR_NAME" \ # create a key pair, or use other mechanism of getting on to the box
--block-device-mappings '{"DeviceName":"/dev/sda1","Ebs":{"Encrypted":false,"DeleteOnTermination":true,"Iops":3000,"SnapshotId":"snap-0fe84a34403e3da8b","VolumeSize":200,"VolumeType":"gp3","Throughput":125}}' \
--network-interfaces '{"AssociatePublicIpAddress":true,"DeviceIndex":0,"Groups":["insert-sg-group"]}' \
--tag-specifications '{"ResourceType":"instance","Tags":[{"Key":"Name","Value":"qemu-pg-image"}]}' \
--metadata-options '{"HttpEndpoint":"enabled","HttpPutResponseHopLimit":2,"HttpTokens":"required"}' \
--private-dns-name-options '{"HostnameType":"ip-name","EnableResourceNameDnsARecord":true,"EnableResourceNameDnsAAAARecord":false}' \
--count "1"

```
## Install deps

On the instance, install the dependencies we require for producing QEMU artifacts. Assuming you are the root user:

```bash
apt-get update
apt-get install -y qemu-system qemu-system-arm qemu-utils qemu-efi-aarch64 libvirt-clients libvirt-daemon libqcow-utils software-properties-common git make libnbd-bin nbdkit fuse2fs cloud-image-utils awscli
usermod -aG kvm ubuntu
curl -fsSL https://apt.releases.hashicorp.com/gpg | apt-key add -
apt-add-repository "deb [arch=arm64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
apt-get update && apt-get install packer=1.11.2-1
apt-get install -y docker.io
```

Some dev deps that might be useful:

```bash
apt-get install -y emacs ripgrep vim-tiny byobu
```

## Clone repo and build

Logout/login first to pick up new group memberships!

``` bash
git clone https://github.com/supabase/postgres.git
cd postgres
git checkout da/qemu-rebasing # choose appropriate branch here
make init container-disk-image
```

### Build process

The current AMI process involves a few steps:

1. nix package is build and published using GHA (`.github/workflows/nix-build.yml`)
  - this builds Postgres alongwith the PG extensions we use.
2. "stage1" build (`amazon-arm64-nix.pkr.hcl`, invoked via `.github/workflows/ami-release-nix.yml`)
  - uses an upstream Ubuntu image to initialize the AMI
  - installs and configures the majority of the software that gets shipped as part of the AMI (e.g. gotrue, postgrest, ...)
3. "stage2" build (`stage2-nix-psql.pkr.hcl`, invoked via `.github/workflows/ami-release-nix.yml`)
  - uses the image published from (2)
  - installs and configures the software that is build and published using nix in (1)
  - cleans up build dependencies etc

The QEMU artifact process collapses (2) and (3):

a. nix package is build and published using GHA (`.github/workflows/nix-build.yml`)
b. packer build (`qemu-arm64-nix.pkr.hcl`)
  - uses an upstream Ubuntu live image as the base
  - performs the work that was performed as part of the "stage1" and "stage2" builds
  - this work is executed using `ebssurrogate/scripts/qemu-bootstrap-nix.sh`

## Publish image for later use

Following `make init container-disk-image`, the generated image should be found in: `/path/to/postgres/output-cloudimg`. For portability the image is also bundled up as a docker image with the name: `supabase-postgres-test` . Publish the built docker image to a registry of your choosing, and use the published image with KubeVirt.

# Iterating on the QEMU artifact

For a tighter iteration loop on the Postgres artifact, the recommended workflow is to do so on an Ubuntu bare-metal node that's part of the EKS cluster that you're deploying to.

- Instead of running `make init container-disk-image`, use `make init host-disk` instead to build the raw image file on disk. (`/path/to/postgres/disk/focal-raw.img`)
- Update the VM spec to use `hostDisk` instead of `containerDisk`
    - Note that only one VM can use an image at a time, so you can't create multiple VMs backed by the same host disk.
- Enable the `HostDisk` feature flag for KubeVirt
- Deploy the VM to the node

Additionally, to iterate on the container image part of things, you can build the image on the bare-metal node (`eks-node-container-disk-image` target), rather than needing to publish it to ECR or similar registry. However, this part can take a while, so iterating using host disks remains the fastest dev loop.

## Dependencies note

Installing `docker.io` on an EKS node might interfere with the k8s setup of the node. You can instead install `nerdctl` and `buildkit`:

```bash
curl -L -O https://github.com/containerd/nerdctl/releases/download/v2.0.0/nerdctl-2.0.0-linux-arm64.tar.gz
tar -xzf nerdctl-2.0.0-linux-arm64.tar.gz
mv ./nerdctl /usr/local/bin/
curl -O -L https://github.com/moby/buildkit/releases/download/v0.17.1/buildkit-v0.17.1.linux-arm64.tar.gz
tar -xzf buildkit-v0.17.1.linux-arm64.tar.gz
mv bin/* /usr/local/bin/
```

You'll need to run buildkit: `buildkitd`
