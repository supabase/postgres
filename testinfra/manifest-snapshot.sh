#!/bin/sh
set -eu

if [ "${1:-}" = "--docker" ]; then
	exec docker run --rm -v "$(realpath "$0"):/manifest-snapshot.sh:ro" "$2" sh /manifest-snapshot.sh
fi

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
bsdtar --format=mtree \
	--options='!all,type,mode,uid,gid,sha256digest,link' \
	--exclude=./dev --exclude=./proc --exclude=./run --exclude=./sys --exclude=./tmp --exclude=./var/log --exclude=./data \
	-cf - . 2>/dev/null | sort

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
