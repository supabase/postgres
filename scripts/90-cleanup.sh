#!/bin/bash
set -o errexit

# Ensure /tmp exists and has proper permissions
if [[ ! -d /tmp ]]; then
  mkdir /tmp
fi
chmod 1777 /tmp

# Update system
if [ -n "$(command -v apt-get)" ]; then
  # Remove ansible PPA directly (software-properties-common may not be installed)
  rm -f /etc/apt/sources.list.d/ansible-ubuntu-ansible-*.list \
        /etc/apt/sources.list.d/ansible-ubuntu-ansible-*.sources 2>/dev/null || true

  apt-get -y update
  apt-get -y upgrade
  apt-get -y autoremove
  apt-get -y autoclean
fi

# Clean temp files
rm -rf /tmp/* /var/tmp/*

# Clear history
history -c
cat /dev/null > /root/.bash_history
unset HISTFILE

# Clean logs
find /var/log -mtime -1 -type f -exec truncate -s 0 {} \;
rm -rf /var/log/*.gz /var/log/*.[0-9] /var/log/*-????????

# Clean cloud-init for fresh start
rm -rf /var/lib/cloud/instances/*

# Remove SSH keys (cloud-init regenerates on boot)
rm -f /root/.ssh/authorized_keys /etc/ssh/*key*
touch /etc/ssh/revoked_keys
chmod 600 /etc/ssh/revoked_keys

# Securely erase unused disk space
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
while [ -d /proc/$PID ]; do
  printf "."
  sleep 5
done
sync; rm /zerofile; sync

cat /dev/null > /var/log/lastlog
cat /dev/null > /var/log/wtmp
