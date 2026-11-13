# shellcheck shell=bash

set -euxo pipefail

# nix-built qemu resolves its libraries via RPATH; an inherited
# LD_LIBRARY_PATH (e.g. from a devshell) can inject a mismatched glibc and
# break `qemu-system-* --version`, so drop it.
unset LD_LIBRARY_PATH

postgres_major_version=${1:-}
if [ -z "$postgres_major_version" ]; then
	echo "Usage: build-qemu-image <postgres-major-version> [arch]" >&2
	exit 1
fi

case $(uname -o) in
Darwin) accel=hvf ;;
GNU/Linux) accel=kvm ;;
*) echo "Error: Invalid os '$(uname -o)'. Must be Darwin or Linux" >&2 && exit 1 ;;
esac

declare -A host2arch=([aarch64]=arm64 [x86_64]=amd64)
host=${host2arch[$(uname -m)]}
arch=${2:-$host}
case $arch in
amd64)
	qemu=$(which qemu-system-x86_64)
	code=${qemu%/bin/*}/share/qemu/edk2-x86_64-code.fd
	vars=${qemu%/bin/*}/share/qemu/edk2-i386-vars.fd
	;;
arm64)
	qemu=$(which qemu-system-aarch64)
	code=${qemu%/bin/*}/share/qemu/edk2-aarch64-code.fd
	vars=${qemu%/bin/*}/share/qemu/edk2-arm-vars.fd
	;;
*) echo "Error: Invalid arch '$arch'. Must be 'amd64' or 'arm64'" >&2 && exit 1 ;;
esac

case $arch:$(uname -m) in
amd64:aarch64) machine=q35 cpu=qemu64 ;;
amd64:x86_64) machine=q35 cpu=host ;;
arm64:aarch64) machine=virt,gic-version=max,highmem=on cpu=host ;;
arm64:x86_64) machine=virt,gic-version=max,highmem=on cpu=cortex-a76 ;;
esac
machine+=,accel=$accel
if [[ -z ${BUILD_QEMU_IMAGE_HW_VIRT_ONLY:-} ]]; then
	machine+=:tcg
fi

# stays in the invoking directory (absolute, since we cd into the sources below) because callers pick up the output from there
workdir=$(mktemp -d "$PWD/packer-work-qemu-XXXXXX")
install --mode 444 "$code" "$workdir/ovmf_code.fd"
install --mode 644 "$vars" "$workdir/ovmf_vars.fd" # qemu writes to the vars pflash during boot

git_sha=${GIT_SHA:-$(git rev-parse HEAD)}
system=$([[ $arch == arm64 ]] && echo aarch64-linux || echo x86_64-linux)

nix_store_paths=$(cat "$(nix build --no-link --print-out-paths "github:supabase/postgres/$git_sha#packages.$system.nix-store-paths-$postgres_major_version")")

# packer reads ansible, migrations, etc. relative to the working directory
cd @qemuSources@

postgres_version=$(yq -er ".postgres_release.postgres$postgres_major_version" ansible/postgres_release.yml)

# Build the cloud-init seed ISO before invoking packer.
cloud-localds "$workdir/seeds-cloudimg.iso" nix/packages/build-qemu-image/user-data-cloudimg nix/packages/build-qemu-image/meta-data

if ! SUPA_TRIPWIRE_URL=$(aws s3 presign --region ap-southeast-1 --expires-in 3600 "s3://supabase-internal-artifacts/supa-tripwire/supa-tripwire-v$(yq -er .supa_tripwire_release ansible/vars.yml)-$arch.tar.xz"); then
	echo "::warning::could not presign the supa-tripwire archive, building without supa-tripwire" >&2
	SUPA_TRIPWIRE_URL=
fi
export SUPA_TRIPWIRE_URL
export LC_ALL=C.UTF-8
export PACKER_CACHE_DIR=${PACKER_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/packer} # the sources are read-only, so packer can't keep its default ./packer_cache there
export TZ=UTC
packer init packer/qemu.pkr.hcl
PACKER_LOG=${PACKER_LOG:-1} packer build \
	-var "arch=$arch" \
	-var "cpu=$cpu" \
	-var "machine=$machine" \
	-var "nix_store_paths=$nix_store_paths" \
	-var "postgres-version=$postgres_version" \
	-var "postgres_major_version=$postgres_major_version" \
	-var "qemu_binary=$qemu" \
	-var "workdir=$workdir" \
	packer/qemu.pkr.hcl
