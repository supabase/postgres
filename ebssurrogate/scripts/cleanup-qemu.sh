#!/bin/bash

# DigitalOcean Marketplace Image Validation Tool
# © 2021 DigitalOcean LLC.
# This code is licensed under Apache 2.0 license (see LICENSE.md for details)

set -ex

# Ensure /tmp exists and has the proper permissions before
# checking for security updates
# https://github.com/digitalocean/marketplace-partners/issues/94
if [[ ! -d /tmp ]]; then
	mkdir /tmp
fi
chmod 1777 /tmp

# Cleanup more packages
apt-get -y remove --purge \
	automake \
	autoconf \
	autotools-dev \
	cmake-data \
	cpp-9 \
	cpp-10 \
	gcc-9 \
	gcc-10 \
	git \
	git-man \
	ansible \
	libicu-dev \
	libcgal-dev \
	libgcc-9-dev \
	ansible \
	snapd

if [[ $(uname -m) == aarch64 ]]; then
	apt-get -y remove --purge libgcc-8-dev
fi

# add-apt-repository --yes --remove ppa:ansible/ansible

apt-mark manual libevent-2.1-7t64

apt-get remove -y --purge ansible-core apport appstream bash-completion bcache-tools bind9-dnsutils bind9-host bind9-libs bolt btrfs-progs byobu command-not-found console-setup distro-info eject fonts-ubuntu-console friendly-recovery ftp fwupd gawk gdisk keyboard-configuration libvolume-key1 libssl-dev lvm2 lxd-agent-loader man-db mdadm modemmanager mtd-utils nano netcat-openbsd nfs-common ntfs-3g parted pastebinit screen strace thin-provisioning-tools tmux usb-modeswitch vim vim-runtime wget whiptail xfsprogs

apt remove -y --purge libc6-dev linux-libc-dev libevent-dev libpcre3-dev libsystemd-dev packagekit multipath-tools unattended-upgrades plymouth gnupg open-vm-tools xauth lxd-installer publicsuffix libclang-cpp18 python3-twisted python-babel-localedata libicu74 python3-pygments fonts-dejavu* python3-botocore

apt-get remove -y --purge linux-headers*

apt-get -y autoremove
apt-get -y autoclean
apt-get -y update
apt-get -y upgrade

systemctl set-default multi-user.target
systemctl disable getty@tty1.service
systemctl mask getty@tty1.service
systemctl mask graphical.target

rm -rf /tmp/* /var/tmp/*
history -c
cat /dev/null >/root/.bash_history
unset HISTFILE

journalctl --rotate
journalctl --vacuum-time=1s
find /var/log -mtime -1 -type f -exec truncate -s 0 {} \;
rm -rf /var/log/*.gz /var/log/*.[0-9] /var/log/*-????????
rm -rf /var/lib/cloud/instances/*
rm -f /root/.ssh/authorized_keys /etc/ssh/*key*
touch /etc/ssh/revoked_keys
chmod 600 /etc/ssh/revoked_keys

cat /dev/null >/var/log/lastlog
cat /dev/null >/var/log/wtmp

dd if=/dev/zero of=/zerofile &
PID=$!
while [ -d /proc/$PID ]; do
	printf "."
	sleep 5
done
sync
rm /zerofile
sync

fstrim /
