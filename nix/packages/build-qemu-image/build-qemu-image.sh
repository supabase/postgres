# shellcheck shell=bash

# nix-built qemu resolves its libraries via RPATH; an inherited
# LD_LIBRARY_PATH (e.g. from a devshell) can inject a mismatched glibc and
# break `qemu-system-* --version`, so drop it.
unset LD_LIBRARY_PATH

postgres_major_version=${1:-}
if [ -z "$postgres_major_version" ]; then
	echo "Usage: build-qemu-image <postgres-major-version> [arch]" >&2
	exit 1
fi

qemu=$(which qemu-system-aarch64)
code=${qemu%/bin/*}/share/qemu/edk2-aarch64-code.fd
vars=${qemu%/bin/*}/share/qemu/edk2-arm-vars.fd

workdir=$(mktemp -d packer-work-qemu-XXXXXX)
install --mode 444 "$code" "$workdir/ovmf_code.fd"
install --mode 644 "$vars" "$workdir/ovmf_vars.fd" # qemu writes to the vars pflash during boot

git_sha=${GIT_SHA:-$(git rev-parse HEAD)}
postgres_version=$(yq -r ".postgres_release[\"postgres$postgres_major_version\"]" ansible/vars.yml)

# Build the cloud-init seed ISO before invoking packer.
cloud-localds "$workdir/seeds-cloudimg.iso" user-data-cloudimg meta-data

export LC_ALL=C.UTF-8
export TZ=UTC
packer init qemu-arm64-nix.pkr.hcl
PACKER_LOG=${PACKER_LOG:-1} packer build \
	-var "git_sha=$git_sha" \
	-var "postgres-version=$postgres_version" \
	-var "postgres_major_version=$postgres_major_version" \
	-var "workdir=$workdir" \
	qemu-arm64-nix.pkr.hcl
