#!/bin/sh
set -eu

INSTALLED=0
if ! command -v bsdtar >/dev/null 2>&1; then
	DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends libarchive-tools >/dev/null
	INSTALLED=1
fi

cd /
bsdtar --format=mtree \
	--options='!all,type,mode,uid,gid,sha256digest,link' \
	--exclude=./dev --exclude=./proc --exclude=./run --exclude=./sys --exclude=./tmp --exclude=./var/log --exclude=./data \
	-cf - . 2>/dev/null | sort

if [ "$INSTALLED" = 1 ]; then
	DEBIAN_FRONTEND=noninteractive apt-get remove -y --purge libarchive-tools >/dev/null
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
