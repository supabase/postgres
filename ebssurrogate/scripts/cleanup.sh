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

if [ -n "$(command -v yum)" ]; then
	yum update -y
	yum clean all
elif [ -n "$(command -v apt-get)" ]; then
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
		ansible

	# add-apt-repository --yes --remove ppa:ansible/ansible

	apt-get -y update
	apt-get -y upgrade
	apt-get -y autoremove
	apt-get -y autoclean
fi
rm -rf /tmp/* /var/tmp/*
history -c
cat /dev/null >/root/.bash_history
unset HISTFILE
find /var/log -mtime -1 -type f -exec truncate -s 0 {} \;
rm -rf /var/log/*.gz /var/log/*.[0-9] /var/log/*-????????
rm -rf /var/lib/cloud/instances/*
rm -f /root/.ssh/authorized_keys /etc/ssh/*key*
touch /etc/ssh/revoked_keys
chmod 600 /etc/ssh/revoked_keys

# Note: the upstream DigitalOcean version of this script zero-fills the free
# space here ("secure erase"). That is intentionally removed for the AMI
# build: EBS snapshots only store written blocks, so zero-filling rewrites
# the entire root volume serially (slow) and inflates the snapshot with
# blocks of zeros (bigger artifact), while the freshly-debootstrapped image
# holds no secrets to erase.
sync
cat /dev/null >/var/log/lastlog
cat /dev/null >/var/log/wtmp
