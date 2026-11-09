#!/bin/sh
set -eu

INSTALLED=0
if ! command -v bsdtar >/dev/null 2>&1; then
	if command -v apt-get >/dev/null 2>&1; then
		DEBIAN_FRONTEND=noninteractive apt-get update -qq >/dev/null
		DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends libarchive-tools >/dev/null
	elif command -v apk >/dev/null 2>&1; then
		apk add --no-cache libarchive-tools >/dev/null
	fi
	INSTALLED=1
fi

cd /
{
	bsdtar --format=mtree \
		--options='!all,type,mode,uid,gid,sha256digest,link' \
		--exclude=./dev --exclude=./proc --exclude=./run --exclude=./sys --exclude=./tmp --exclude=./var/log --exclude=./data \
		--exclude='./etc/ssh/ssh_host_*' --exclude=./etc/machine-id --exclude=./nix/store/.links \
		--exclude=./etc/fstab --exclude=./boot/grub/grub.cfg \
		-cf - . 2>/dev/null
	for f in ./etc/fstab ./boot/grub/grub.cfg; do
		[ -f "$f" ] || continue
		h=$(sed -E 's/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}|[0-9A-F]{4}-[0-9A-F]{4}/UUID/g' "$f" | sha256sum | cut -d' ' -f1)
		echo "$f type=file uuid-normalized sha256digest=$h"
	done
} | sort

if [ "$INSTALLED" = 1 ]; then
	if command -v apt-get >/dev/null 2>&1; then
		DEBIAN_FRONTEND=noninteractive apt-get remove -y --purge libarchive-tools >/dev/null
	elif command -v apk >/dev/null 2>&1; then
		apk del libarchive-tools >/dev/null
	fi
fi

echo '--- units ---'
systemctl list-unit-files --no-pager 2>/dev/null | sort
echo '--- users ---'
getent passwd | sort
echo '--- groups ---'
getent group | sort
echo '--- nft ---'
nft list ruleset 2>/dev/null || true
echo '--- sysctl ---'
sysctl -a 2>/dev/null | sort
