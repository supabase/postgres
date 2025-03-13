#!/bin/bash

# DigitalOcean Marketplace Image Validation Tool
# © 2021 DigitalOcean LLC.
# This code is licensed under Apache 2.0 license (see LICENSE.md for details)

set -o errexit

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
	cpp-8  \
	cpp-9  \
	cpp-10  \
	gcc-8  \
	gcc-9  \
	gcc-10  \
	git  \
	git-man  \
	ansible \
	libicu-dev \
	libcgal-dev \
	libgcc-9-dev \
	libgcc-8-dev \
	ansible \
        snapd

  add-apt-repository --yes --remove ppa:ansible/ansible

  source /etc/os-release
  apt-get -y remove --purge linux-headers-5.11.0-1021-aws

  apt-get -y update
  apt-get -y upgrade
  apt-get -y autoremove
  apt-get -y autoclean
fi
rm -rf /tmp/* /var/tmp/*
history -c
cat /dev/null > /root/.bash_history
unset HISTFILE
find /var/log -mtime -1 -type f -exec truncate -s 0 {} \;
rm -rf /var/log/*.gz /var/log/*.[0-9] /var/log/*-????????
rm -rf /var/lib/cloud/instances/*
rm -f /root/.ssh/authorized_keys /etc/ssh/*key*
touch /etc/ssh/revoked_keys
chmod 600 /etc/ssh/revoked_keys

cat /dev/null > /var/log/lastlog
cat /dev/null > /var/log/wtmp
