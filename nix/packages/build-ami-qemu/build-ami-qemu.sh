# shellcheck shell=bash

major=$1
out=$2
repo=$PWD
release=$(yq -r ".postgres_release[\"postgres$major\"]" ansible/vars.yml)
git_sha=${GIT_SHA:-$(git rev-parse origin/develop)}

mkdir -p "$out"
cd "$out"

seed() {
	rm -rf seed
	mkdir -p seed/tmp/ansible-playbook
	touch seed/meta-data
	cat >seed/user-data <<'EOF'
#cloud-config
runcmd:
  - - systemd-run
    - --unit=build
    - --setenv=HOME=/root
    - --property=StandardOutput=journal+console
    - bash
    - -c
    - mkdir -p /media/seed && mount -o ro /dev/disk/by-label/cidata /media/seed && bash -ex /media/seed/run; echo "run exit=$?" >/dev/console; umount /media/seed; rmdir /media/seed; systemctl poweroff
EOF
}

vm() {
	local name=$1 boot=$2
	shift 2
	genisoimage -quiet -output seed.iso -volid cidata -rock seed
	install -m 644 "$VARS" vars.fd
	qemu-system-aarch64 -machine virt,gic-version=max,highmem=on,accel=hvf:kvm -cpu host -smp 8 -m 8192 \
		-display none -no-reboot \
		-chardev stdio,id=console,mux=on,signal=off -serial chardev:console \
		-device pci-serial,chardev=console \
		-drive "if=pflash,format=raw,readonly=on,file=$CODE" \
		-drive "if=pflash,format=raw,file=vars.fd" \
		-drive "file=$boot,if=virtio,discard=unmap,detect-zeroes=unmap" \
		-drive "file=seed.iso,if=virtio,format=raw,readonly=on" \
		"$@" \
		-nic user,model=virtio-net-pci </dev/null | tee "$name.log"
	rm -rf seed seed.iso vars.fd
	if ! grep -q "run exit=0" "$name.log"; then
		echo "Error: $name failed, see $out/$name.log" >&2
		exit 1
	fi
}

drives=()
for disk in root:xvdf:10G data:xvdh:1G build:xvdc:16G; do
	IFS=: read -r name serial size <<<"$disk"
	qemu-img create -q -f qcow2 "$name.qcow2" "$size"
	drives+=(
		-drive "file=$name.qcow2,if=none,id=$name,discard=unmap,detect-zeroes=unmap"
		-device "virtio-blk-pci,drive=$name,serial=$serial"
	)
done
qemu-img create -q -f qcow2 -b "$CLOUDIMG" -F qcow2 surrogate.qcow2 10G

seed
cp -r "$repo"/ebssurrogate/files/{ebsnvme-id,70-ec2-nvme-devices.rules,cloud.cfg,vector.timer,apparmor_profiles} "$repo/migrations" seed/tmp/
cp "$repo"/ebssurrogate/scripts/{chroot-bootstrap-nix.sh,cleanup.sh,surrogate-bootstrap-nix.sh} seed/tmp/
cp -r "$repo/ansible" seed/tmp/ansible-playbook/
find seed/tmp -type f -exec chmod a-w {} +
cat >seed/run <<EOF
cat >/etc/udev/rules.d/99-xvd.rules <<'RULE'
KERNEL=="vd*", ENV{ID_SERIAL}=="xvd?", SYMLINK+="\$env{ID_SERIAL}%n"
RULE
udevadm control --reload
udevadm trigger --settle
cp -r /media/seed/tmp/. /tmp/
cd /tmp/ansible-playbook
ARGS="-e postgresql_major=$major" POSTGRES_SUPABASE_VERSION=$release bash /tmp/surrogate-bootstrap-nix.sh
EOF
vm surrogate surrogate.qcow2 "${drives[@]}"
rm surrogate.qcow2 build.qcow2

seed
cp -r "$repo/ansible" "$repo/audit-specs" seed/tmp/ansible-playbook/
cp -r "$repo/migrations" "$repo/ebssurrogate/scripts/nix-provision.sh" seed/tmp/
cat >seed/run <<EOF
systemctl start ssh
install -d -m 700 -o ubuntu -g ubuntu /home/ubuntu/.cache
cp -r /media/seed/tmp/. /tmp/
cd /tmp/ansible-playbook
GIT_SHA=$git_sha POSTGRES_MAJOR_VERSION=$major bash /tmp/nix-provision.sh
rm /tmp/nix-provision.sh
cloud-init clean --logs
EOF
vm provision root.qcow2 -drive "file=data.qcow2,if=virtio,discard=unmap,detect-zeroes=unmap"

if [[ -n ${GITHUB_OUTPUT:-} ]]; then
	read -r bytes human < <(sed -nE 's/.*::notice::disk_usage bytes=([0-9]+) human=([^[:space:]]+).*/\1 \2/p' provision.log | tail -n 1)
	printf 'disk_usage_json={"bytes":"%s","human":"%s"}\n' "$bytes" "$human" >>"$GITHUB_OUTPUT"
fi
