#!/bin/bash

# DigitalOcean Marketplace Image Validation Tool
# © 2021 DigitalOcean LLC.
# This code is licensed under Apache 2.0 license (see LICENSE.md for details)

set -ex

# shellcheck source=/dev/null
source /tmp/provision-common.sh

# Ensure /tmp exists and has the proper permissions before
# checking for security updates
# https://github.com/digitalocean/marketplace-partners/issues/94
ensure_tmp_dir

# Cleanup more packages
packages=(
	ansible-core
	apport
	appstream
	bash-completion
	bcache-tools
	bind9-dnsutils
	bind9-host
	bind9-libs
	bolt
	btrfs-progs
	byobu
	command-not-found
	console-setup
	distro-info
	eject
	'fonts-dejavu*'
	fonts-ubuntu-console
	friendly-recovery
	ftp
	fwupd
	gawk
	gdisk
	gnupg
	keyboard-configuration
	libc6-dev
	libclang-cpp18
	libevent-dev
	libicu74
	libpcre3-dev
	libssl-dev
	libsystemd-dev
	libvolume-key1
	'linux-headers*'
	linux-libc-dev
	lvm2
	lxd-agent-loader
	lxd-installer
	man-db
	mdadm
	modemmanager
	mtd-utils
	multipath-tools
	nano
	netcat-openbsd
	nfs-common
	ntfs-3g
	open-vm-tools
	packagekit
	parted
	pastebinit
	plymouth
	publicsuffix
	python-babel-localedata
	python3-botocore
	python3-pygments
	python3-twisted
	screen
	snapd
	strace
	thin-provisioning-tools
	tmux
	unattended-upgrades
	usb-modeswitch
	vim
	vim-runtime
	wget
	whiptail
	xauth
	xfsprogs
)

apt-mark manual libevent-2.1-7t64
purge_packages "${packages[@]}"

systemctl set-default multi-user.target
systemctl disable getty@tty1.service
systemctl mask getty@tty1.service
systemctl mask graphical.target

scrub_history

journalctl --rotate
journalctl --vacuum-time=1s
scrub_logs_and_keys

zero_free_space
empty_login_records

fstrim /
