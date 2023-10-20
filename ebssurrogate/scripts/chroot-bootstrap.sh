#!/usr/bin/env bash
#
# This script runs inside chrooted environment. It installs grub and its
# Configuration file.
#

set -o errexit
set -o pipefail
set -o xtrace

export DEBIAN_FRONTEND=noninteractive

export APT_OPTIONS="-oAPT::Install-Recommends=false \
		  -oAPT::Install-Suggests=false \
		    -oAcquire::Languages=none"

if [ $(dpkg --print-architecture) = "amd64" ]; 
then 
	ARCH="amd64";
else
	ARCH="arm64";
fi



function update_install_packages {
	source /etc/os-release
	if [ "${UBUNTU_CODENAME}" = "bionic" ]; then
		sed -i 's/focal/bionic/g' /etc/apt/sources.list
	fi

	# Update APT with new sources
	cat /etc/apt/sources.list
	apt-get $APT_OPTIONS update && apt-get $APT_OPTIONS --yes dist-upgrade

	# Do not configure grub during package install
	if [ "${ARCH}" = "amd64" ]; then
		echo 'grub-pc grub-pc/install_devices_empty select true' | debconf-set-selections
		echo 'grub-pc grub-pc/install_devices select' | debconf-set-selections
	# Install various packages needed for a booting system
		apt-get install -y \
		linux-aws \
		grub-pc \
		e2fsprogs
	else
		apt-get install -y e2fsprogs
	fi
	# Install standard packages
	apt-get install -y \
		sudo \
		wget \
		cloud-init \
		acpid \
		ec2-hibinit-agent \
		ec2-instance-connect \
		hibagent \
		ncurses-term \
		ssh-import-id \

	# apt upgrade
	apt-get upgrade -y

	# Install OpenSSH and other packages
	sudo add-apt-repository universe
	apt-get update
	apt-get install -y --no-install-recommends \
		openssh-server \
		git \
		ufw \
		cron \
		logrotate \
		fail2ban \
		locales \
		at \
		less \
		python3-systemd

	if [ "${ARCH}" = "arm64" ]; then
		apt-get $APT_OPTIONS --yes install linux-aws initramfs-tools dosfstools
	fi

	if [ "${UBUNTU_CODENAME}" = "bionic" ]; then
		echo "deb [trusted=yes] http://apt.llvm.org/bionic/ llvm-toolchain-bionic-12 main" >> /etc/apt/sources.list
		wget -O - https://apt.llvm.org/llvm-snapshot.gpg.key | apt-key add -
		add-apt-repository --yes --update ppa:ubuntu-toolchain-r/test
		
		# Install cmake 3.12+
		wget -O - https://apt.kitware.com/keys/kitware-archive-latest.asc 2>/dev/null | sudo apt-key add -
		apt-add-repository --yes --update 'deb https://apt.kitware.com/ubuntu/ bionic main'

		apt-get $APT_OPTIONS update
	fi
}

function setup_locale {
cat << EOF > /etc/default/locale
LANG="C.UTF-8"
LC_CTYPE="C.UTF-8"
EOF
	localedef -i en_US -f UTF-8 en_US.UTF-8
}

function install_packages_for_build {
	apt-get install -y --no-install-recommends linux-libc-dev \
	 acl \
	 magic-wormhole sysstat \
	 build-essential libreadline-dev zlib1g-dev flex bison libxml2-dev libxslt-dev libssl-dev libsystemd-dev libpq-dev libxml2-utils uuid-dev xsltproc ssl-cert \
	 gcc-10 g++-10 \
	 libgeos-dev libproj-dev libgdal-dev libjson-c-dev libboost-all-dev libcgal-dev libmpfr-dev libgmp-dev cmake \
	 libkrb5-dev \
	 maven default-jre default-jdk \
	 curl gpp apt-transport-https cmake libc++-dev libc++abi-dev libc++1 libglib2.0-dev libtinfo5 libc++abi1 ninja-build python \
	 liblzo2-dev

	source /etc/os-release
	if [ "${UBUNTU_CODENAME}" = "bionic" ]; then
		apt-get install -y --no-install-recommends llvm-12-dev clang-12 cmake
		apt-mark manual libllvm12:arm64
	else 
		apt-get install -y --no-install-recommends llvm-11-dev clang-11
		# Mark llvm as manual to prevent auto removal
		apt-mark manual libllvm11:arm64
	fi
}

function setup_apparmor {
	apt-get install -y apparmor apparmor-utils auditd

	# Copy apparmor profiles
	cp -rv /tmp/apparmor_profiles/* /etc/apparmor.d/
}

function setup_grub_conf_arm64 {
cat << EOF > /etc/default/grub
GRUB_DEFAULT=0
GRUB_TIMEOUT=0
GRUB_TIMEOUT_STYLE="hidden"
GRUB_DISTRIBUTOR="Supabase postgresql"
GRUB_CMDLINE_LINUX_DEFAULT="nomodeset console=tty1 console=ttyS0 ipv6.disable=0"
EOF
}

# Install GRUB
function install_configure_grub {
	if [ "${ARCH}" = "arm64" ]; then
		apt-get $APT_OPTIONS --yes install cloud-guest-utils fdisk grub-efi-arm64 efibootmgr
		setup_grub_conf_arm64
		rm -rf /etc/grub.d/30_os-prober
		sleep 1
	fi
	grub-install /dev/xvdf && update-grub
}

# skip fsck for first boot
function disable_fsck {
	touch /fastboot
}

# Don't request hostname during boot but set hostname
function setup_hostname {
	sed -i 's/gethostname()/ubuntu /g' /etc/dhcp/dhclient.conf
	sed -i 's/host-name,//g' /etc/dhcp/dhclient.conf
	echo "ubuntu" > /etc/hostname
	chmod 644 /etc/hostname
}

# Set options for the default interface
function setup_eth0_interface {
cat << EOF > /etc/netplan/eth0.yaml
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: true
EOF
}

function disable_sshd_passwd_auth {
	sed -i -E -e 's/^#?\s*PasswordAuthentication\s+(yes|no)\s*$/PasswordAuthentication no/g' \
	  -e 's/^#?\s*ChallengeResponseAuthentication\s+(yes|no)\s*$/ChallengeResponseAuthentication no/g' \
	 /etc/ssh/sshd_config
}

function create_admin_account {
	groupadd admin
}

#Set default target as multi-user
function set_default_target {
	rm -f /etc/systemd/system/default.target
	ln -s /lib/systemd/system/multi-user.target /etc/systemd/system/default.target
}

# Setup ccache
function setup_ccache {
	apt-get install ccache -y
	mkdir -p /tmp/ccache
	export PATH=/usr/lib/ccache:$PATH
	echo "PATH=$PATH" >> /etc/environment
}

# Clear apt caches
function cleanup_cache {
	apt-get clean
}

update_install_packages
setup_locale
#install_packages_for_build
install_configure_grub
setup_apparmor
setup_hostname
create_admin_account
set_default_target
setup_eth0_interface
disable_sshd_passwd_auth
disable_fsck
#setup_ccache
cleanup_cache
