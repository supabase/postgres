# shellcheck shell=bash

postgres_major_version=${1:-}
if [ -z "$postgres_major_version" ]; then
	echo "Usage: build-ami-qemu <postgres-major-version> [arch]" >&2
	exit 1
fi

declare -A host2arch=([aarch64]=arm64 [arm64]=arm64 [x86_64]=amd64)
host=${host2arch[$(uname -m)]}
arch=${2:-$host}
case $arch in
amd64)
	qemu=$(which qemu-system-x86_64)
	code=${qemu%/bin/*}/share/qemu/edk2-x86_64-code.fd
	vars=${qemu%/bin/*}/share/qemu/edk2-i386-vars.fd
	cloudimg=$CLOUDIMG_AMD64
	ami_arch=x86_64 boot_mode=legacy-bios
	;;
arm64)
	qemu=$(which qemu-system-aarch64)
	code=${qemu%/bin/*}/share/qemu/edk2-aarch64-code.fd
	vars=${qemu%/bin/*}/share/qemu/edk2-arm-vars.fd
	cloudimg=$CLOUDIMG_ARM64
	ami_arch=arm64 boot_mode=uefi
	;;
*) echo "Error: Invalid arch '$arch'. Must be 'amd64' or 'arm64'" >&2 && exit 1 ;;
esac

case $arch:$host in
amd64:arm64) machine=q35 cpu=qemu64 ;;
amd64:amd64) machine=q35 cpu=host ;;
arm64:arm64) machine=virt,gic-version=max,highmem=on cpu=host ;;
arm64:amd64) machine=virt,gic-version=max,highmem=on cpu=cortex-a76 ;;
esac
machine+=,accel=hvf:kvm
if [[ -z ${BUILD_AMI_QEMU_HW_VIRT_ONLY:-} ]]; then
	machine+=:tcg
fi

workdir=$(mktemp -d "$PWD/packer-work-ami-qemu-XXXXXX")
postgres_version=$(yq -r ".postgres_release[\"postgres$postgres_major_version\"]" ansible/vars.yml)
git_sha=${GIT_SHA:-$(git rev-parse origin/develop)}

run_vm() {
	local name=$1 user_data=$2 seed=$workdir/$1-seed
	shift 2
	cp "$user_data" "$seed/user-data"
	touch "$seed/meta-data"
	genisoimage -quiet -output "$workdir/$name.iso" -volid cidata -rock "$seed"
	install --mode 644 "$vars" "$workdir/$name-vars.fd"
	"$qemu" -machine "$machine" -cpu "$cpu" -smp 8 -m 8192 -display none -no-reboot \
		-chardev stdio,id=console,mux=on,signal=off -serial chardev:console \
		-device pci-serial,chardev=console \
		-drive "if=pflash,format=raw,readonly=on,file=$code" \
		-drive "if=pflash,format=raw,file=$workdir/$name-vars.fd" \
		-drive "file=$workdir/$name.iso,if=virtio,format=raw,readonly=on" \
		-nic user,model=virtio-net-pci \
		"$@" </dev/null | tee "$workdir/$name.log"
	if ! grep -q "$name exit=0" "$workdir/$name.log"; then
		echo "Error: $name failed, see $workdir/$name.log" >&2
		exit 1
	fi
	rm -rf "$seed" "$workdir/$name.iso" "$workdir/$name-vars.fd"
}

seed=$workdir/surrogate-bootstrap-seed
mkdir -p "$seed/tmp/ansible-playbook"
cp -r ebssurrogate/files/{ebsnvme-id,70-ec2-nvme-devices.rules,cloud.cfg,vector.timer,apparmor_profiles} migrations "$seed/tmp/"
cp ebssurrogate/scripts/{chroot-bootstrap-nix.sh,cleanup.sh,surrogate-bootstrap-nix.sh} "$seed/tmp/"
cp -r ansible "$seed/tmp/ansible-playbook/"
printf 'export ARGS=%q\nexport POSTGRES_SUPABASE_VERSION=%q\n' \
	"-e postgresql_major=$postgres_major_version" "$postgres_version" >"$seed/tmp/env"

qemu-img create -q -f qcow2 -b "$cloudimg" -F qcow2 "$workdir/surrogate.qcow2" 10G
drives=()
for disk in root:xvdf:10G data:xvdh:1G build:xvdc:16G; do
	IFS=: read -r name serial size <<<"$disk"
	qemu-img create -q -f qcow2 "$workdir/$name.qcow2" "$size"
	drives+=(
		-drive "file=$workdir/$name.qcow2,if=none,id=$name,format=qcow2,discard=unmap,detect-zeroes=unmap"
		-device "virtio-blk-pci,drive=$name,serial=$serial"
	)
done
run_vm surrogate-bootstrap ebssurrogate/files/qemu-surrogate-user-data \
	-drive "file=$workdir/surrogate.qcow2,if=virtio,format=qcow2,discard=unmap" \
	"${drives[@]}"
rm "$workdir/surrogate.qcow2" "$workdir/build.qcow2"

seed=$workdir/nix-provision-seed
mkdir -p "$seed/tmp/ansible-playbook"
cp -r ansible audit-specs "$seed/tmp/ansible-playbook/"
cp -r migrations ebssurrogate/scripts/nix-provision.sh "$seed/tmp/"
printf 'export GIT_SHA=%q\nexport POSTGRES_MAJOR_VERSION=%q\n' "$git_sha" "$postgres_major_version" >"$seed/tmp/env"
run_vm nix-provision ebssurrogate/files/qemu-stage2-user-data \
	-drive "file=$workdir/root.qcow2,if=virtio,format=qcow2,discard=unmap,detect-zeroes=unmap" \
	-drive "file=$workdir/data.qcow2,if=virtio,format=qcow2,discard=unmap,detect-zeroes=unmap"

echo "root: $workdir/root.qcow2"
echo "data: $workdir/data.qcow2"

if [[ -z ${AMI_NAME_PREFIX:-} ]]; then
	exit 0
fi

for name in root data; do
	qemu-img convert -O raw "$workdir/$name.qcow2" "$workdir/$name.raw"
done
root_snapshot=$(coldsnap upload --wait --omit-zero-blocks --no-progress "$workdir/root.raw")
data_snapshot=$(coldsnap upload --wait --omit-zero-blocks --no-progress "$workdir/data.raw")
ami_id=$(aws ec2 register-image \
	--name "$AMI_NAME_PREFIX-qemu-$postgres_version" \
	--architecture "$ami_arch" \
	--boot-mode "$boot_mode" \
	--ena-support \
	--virtualization-type hvm \
	--root-device-name /dev/xvda \
	--block-device-mappings \
	"DeviceName=/dev/xvda,Ebs={SnapshotId=$root_snapshot,VolumeSize=10,VolumeType=gp3,Iops=3000,Throughput=125,DeleteOnTermination=true}" \
	"DeviceName=/dev/xvdh,Ebs={SnapshotId=$data_snapshot,VolumeSize=1,VolumeType=gp3,DeleteOnTermination=true}" \
	--query ImageId --output text) || {
	aws ec2 delete-snapshot --snapshot-id "$root_snapshot"
	aws ec2 delete-snapshot --snapshot-id "$data_snapshot"
	exit 1
}
aws ec2 create-tags --resources "$ami_id" "$root_snapshot" "$data_snapshot" --tags \
	Key=creator,Value=packer \
	Key=appType,Value=postgres \
	"Key=postgresVersion,Value=$postgres_version" \
	"Key=sourceSha,Value=${SOURCE_SHA:-$git_sha}" \
	"Key=packerExecutionId,Value=${PACKER_EXECUTION_ID:-}"
echo "ami: $ami_id"

read -r disk_usage_bytes disk_usage_human < <(
	sed -nE 's/.*::notice::disk_usage bytes=([0-9]+) human=([^[:space:]]+).*/\1 \2/p' "$workdir/nix-provision.log" | tail -n 1
)
if [[ -n ${GITHUB_OUTPUT:-} ]]; then
	{
		echo "stage2_ami_id=$ami_id"
		printf 'disk_usage_json={"bytes":"%s","human":"%s"}\n' "$disk_usage_bytes" "$disk_usage_human"
	} >>"$GITHUB_OUTPUT"
fi
