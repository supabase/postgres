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
	cpp-9  \
	cpp-10  \
	gcc-9  \
	gcc-10  \
	git  \
	git-man  \
	ansible \
	libicu-dev \
	libcgal-dev \
	libgcc-9-dev \
 	ansible

  # Remove ansible PPA directly (software-properties-common may not be installed)
  rm -f /etc/apt/sources.list.d/ansible-ubuntu-ansible-*.list \
        /etc/apt/sources.list.d/ansible-ubuntu-ansible-*.sources 2>/dev/null || true

  source /etc/os-release

  # Protect critical runtime packages from autoremove
  apt-mark manual libevent-2.1-7t64

  # Ensure cloud-init and openssh-server are installed
  # They may have been removed as dependencies during package cleanup
  apt-get -y install --no-install-recommends cloud-init openssh-server

  # Ensure cloud-init and SSH services are enabled (may not be re-enabled on reinstall)
  systemctl enable cloud-init-local.service cloud-init.service cloud-config.service cloud-final.service ssh.service || true

  # Protect SSH and cloud-init dependencies from autoremove
  # Without these, the AMI won't be accessible via SSH after boot
  apt-mark manual openssh-server cloud-init python3-systemd python3-jinja2 \
    python3-yaml python3-oauthlib python3-configobj python3-requests \
    python3-urllib3 python3-certifi python3-chardet python3-idna || true

  apt-get -y autoremove
  apt-get -y autoclean

  apt-get -y update
  apt-get -y upgrade
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

# Securely erase the unused portion of the filesystem
GREEN='\033[0;32m'
NC='\033[0m'
printf "\n${GREEN}Writing zeros to the remaining disk space to securely
erase the unused portion of the file system.
Depending on your disk size this may take several minutes.
The secure erase will complete successfully when you see:${NC}
    dd: writing to '/zerofile': No space left on device\n
Beginning secure erase now\n"

dd if=/dev/zero of=/zerofile &
  PID=$!
  while [ -d /proc/$PID ]
    do
      printf "."
      sleep 5
    done
sync; rm /zerofile; sync
cat /dev/null > /var/log/lastlog; cat /dev/null > /var/log/wtmp
