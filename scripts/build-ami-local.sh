#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

apt-get install --yes git
git config --global --add safe.directory "$PWD"

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
POSTGRES_MAJOR_VERSION=17
POSTGRES_SUPABASE_VERSION=${POSTGRES_SUPABASE_VERSION:-local}
GIT_SHA=${GIT_SHA:-$(git -C "$ROOT" rev-parse develop)}
ARGS=${ARGS:--e postgresql_major="$POSTGRES_MAJOR_VERSION"}

if [ "$(id -u)" -ne 0 ]; then
	echo "Run this script as root" >&2
	exit 1
fi

cleanup() {
	for path in /mnt/sys /mnt/proc /mnt/dev; do
		if mountpoint -q "$path"; then
			umount --recursive --lazy "$path"
		fi
	done
}
trap cleanup EXIT

rm -rf /tmp/ansible-playbook /tmp/apparmor_profiles /tmp/migrations
mkdir -p /mnt

# fake packer provisioner based setup
cp "$ROOT/ebssurrogate/files/ebsnvme-id" /tmp/ebsnvme-id
cp "$ROOT/ebssurrogate/files/70-ec2-nvme-devices.rules" /tmp/70-ec2-nvme-devices.rules
cp "$ROOT/ebssurrogate/scripts/chroot-bootstrap-nix.sh" /tmp/chroot-bootstrap-nix.sh
cp "$ROOT/ebssurrogate/scripts/cleanup.sh" /tmp/cleanup.sh
cp "$ROOT/ebssurrogate/files/cloud.cfg" /tmp/cloud.cfg
cp "$ROOT/ebssurrogate/files/vector.timer" /tmp/vector.timer
cp -r "$ROOT/ebssurrogate/files/apparmor_profiles" "$ROOT/migrations" /tmp
cp -r "$ROOT/migrations" /tmp/
mkdir -p /tmp/ansible-playbook
cp -r "$ROOT/ansible" /tmp/ansible-playbook/
cp "$ROOT/ansible/vars.yml" /tmp/ansible-playbook/vars.yml

cp "$ROOT/ebssurrogate/scripts/surrogate-bootstrap-nix.sh" /tmp/
export ARGS POSTGRES_MAJOR_VERSION POSTGRES_SUPABASE_VERSION
/tmp/surrogate-bootstrap-nix.sh

rm -rf /mnt/tmp/ansible-playbook /mnt/tmp/migrations

mkdir -p /mnt/tmp/ansible-playbook
cp -r "$ROOT/ansible" /mnt/tmp/ansible-playbook/
cp -r "$ROOT/migrations" /mnt/tmp/
cp -r "$ROOT/audit-specs" /mnt/tmp/ansible-playbook
cp "$ROOT/ebssurrogate/scripts/nix-provision.sh" /mnt/tmp/

mountpoint -q /mnt/dev || mount --rbind /dev /mnt/dev
mountpoint -q /mnt/dev/pts || mount -t devpts devpts /mnt/dev/pts
mountpoint -q /mnt/proc || mount --rbind /proc /mnt/proc
mountpoint -q /mnt/sys || mount --rbind /sys /mnt/sys

chroot /mnt /usr/bin/env \
	ARGS="$ARGS" \
	GIT_SHA="$GIT_SHA" \
	NIX_SECRET_KEY="${NIX_SECRET_KEY:-}" \
	POSTGRES_MAJOR_VERSION="$POSTGRES_MAJOR_VERSION" \
	/tmp/nix-provision.sh
