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

# Prevent services from starting during package installation in chroot
# This avoids hangs from cloud-init, dbus, etc. trying to start services
cat > /usr/sbin/policy-rc.d <<'EOF'
#!/bin/sh
exit 101
EOF
chmod +x /usr/sbin/policy-rc.d

if [ $(dpkg --print-architecture) = "amd64" ];
then
	ARCH="amd64";
else
	ARCH="arm64";
fi

# Get current mirror from sources.list
function get_current_mirror {
	grep -oP 'http://[^/]+(?=/ubuntu-ports/)' /etc/apt/sources.list | head -1 || echo ""
}

# Switch to a different mirror
function switch_mirror {
	local new_mirror="$1"
	local sources_file="/etc/apt/sources.list"

	echo "Switching to mirror: ${new_mirror}"
	sed -i "s|http://[^/]*/ubuntu-ports/|http://${new_mirror}/ubuntu-ports/|g" "${sources_file}"

	# Show what we're using
	echo "Current sources.list configuration:"
	grep -E '^deb ' "${sources_file}" | head -3
}

# Get list of mirrors to try
function get_mirror_list {
	local sources_file="/etc/apt/sources.list"
	local current_region=$(grep -oP '(?<=http://)[^.]+(?=\.clouds\.ports\.ubuntu\.com)' "${sources_file}" | head -1 || echo "")

	local -a mirrors=()

	# Priority order:
	# 1. Country-specific mirror (most reliable)
	# 2. Regional CDN (can be inconsistent)
	# 3. Global fallback

	# Singapore country mirror for ap-southeast-1
	if [ "${current_region}" = "ap-southeast-1" ]; then
		mirrors+=("sg.ports.ubuntu.com")
	fi

	if [ -n "${current_region}" ]; then
		mirrors+=("${current_region}.clouds.ports.ubuntu.com")
	fi

	mirrors+=("ports.ubuntu.com")

	echo "${mirrors[@]}"
}

# Mirror fallback function for resilient apt-get update
function apt_update_with_fallback {
	local sources_file="/etc/apt/sources.list"
	local -a mirror_list=($(get_mirror_list))
	local attempt=1
	local max_attempts=${#mirror_list[@]}

	for mirror in "${mirror_list[@]}"; do
		echo "========================================="
		echo "Attempting apt-get update with mirror: ${mirror}"
		echo "Attempt ${attempt} of ${max_attempts}"
		echo "========================================="

		switch_mirror "${mirror}"

		# Attempt update with timeout (5 minutes)
		if timeout 300 apt-get $APT_OPTIONS update 2>&1; then
			echo "========================================="
			echo "✓ Successfully updated apt cache using mirror: ${mirror}"
			echo "========================================="
			return 0
		else
			local exit_code=$?
			echo "========================================="
			echo "✗ Failed to update using mirror: ${mirror}"
			echo "Exit code: ${exit_code}"
			echo "========================================="

			# Clean partial downloads
			apt-get clean
			rm -rf /var/lib/apt/lists/*

			# Exponential backoff before next attempt
			if [ ${attempt} -lt ${max_attempts} ]; then
				local sleep_time=$((attempt * 5))
				echo "Waiting ${sleep_time} seconds before trying next mirror..."
				sleep ${sleep_time}
			fi
		fi

		attempt=$((attempt + 1))
	done

	echo "========================================="
	echo "ERROR: All mirror tiers failed after ${max_attempts} attempts"
	echo "========================================="
	return 1
}

# Wrapper for apt-get install with mirror fallback on 404 errors
function apt_install_with_fallback {
	local -a mirror_list=($(get_mirror_list))
	local attempt=1
	local max_attempts=${#mirror_list[@]}
	local original_mirror=$(get_current_mirror)

	for mirror in "${mirror_list[@]}"; do
		echo "========================================="
		echo "Attempting apt-get install with mirror: ${mirror}"
		echo "Attempt ${attempt} of ${max_attempts}"
		echo "========================================="

		switch_mirror "${mirror}"

		# Re-run apt-get update to get package lists from new mirror
		if ! timeout 300 apt-get $APT_OPTIONS update 2>&1; then
			echo "Warning: apt-get update failed for mirror ${mirror}, trying next..."
			attempt=$((attempt + 1))
			continue
		fi

		# Run apt-get install directly (no output capture to avoid buffering/timeout issues)
		local exit_code=0
		apt-get "$@" || exit_code=$?

		if [ ${exit_code} -eq 0 ]; then
			echo "========================================="
			echo "✓ Successfully installed packages using mirror: ${mirror}"
			echo "========================================="
			return 0
		fi

		# On failure, check if it's a mirror issue worth retrying
		echo "========================================="
		echo "✗ apt-get failed with exit code: ${exit_code}"
		echo "========================================="

		# Clean apt cache before potential retry
		apt-get clean

		if [ ${attempt} -lt ${max_attempts} ]; then
			local sleep_time=$((attempt * 5))
			echo "Waiting ${sleep_time} seconds before trying next mirror..."
			sleep ${sleep_time}
		fi

		attempt=$((attempt + 1))
	done

	echo "========================================="
	echo "ERROR: All mirror tiers failed for apt-get install after ${max_attempts} attempts"
	echo "========================================="
	return 1
}



function update_install_packages {
	source /etc/os-release

	# Update APT with new sources (using fallback mechanism)
	cat /etc/apt/sources.list
	if ! apt_update_with_fallback; then
		echo "FATAL: Failed to update package lists with any mirror tier"
		exit 1
	fi
	apt-get $APT_OPTIONS --yes dist-upgrade

	# Do not configure grub during package install
	if [ "${ARCH}" = "amd64" ]; then
		echo 'grub-pc grub-pc/install_devices_empty select true' | debconf-set-selections
		echo 'grub-pc grub-pc/install_devices select' | debconf-set-selections
	# Install various packages needed for a booting system (with mirror fallback)
		if ! apt_install_with_fallback install -y linux-aws grub-pc e2fsprogs; then
			echo "FATAL: Failed to install boot packages"
			exit 1
		fi
	else
		if ! apt_install_with_fallback install -y e2fsprogs; then
			echo "FATAL: Failed to install e2fsprogs"
			exit 1
		fi
	fi
	# Install standard packages (with mirror fallback)
	# Note: ec2-hibinit-agent, ec2-instance-connect, hibagent moved to stage 2
	# because their post-install scripts try to access EC2 metadata service
	# which doesn't work in a chroot and causes long hangs
	if ! apt_install_with_fallback install -y \
		sudo \
		wget \
		cloud-init \
		acpid \
		ncurses-term \
		ssh-import-id; then
		echo "FATAL: Failed to install standard packages"
		exit 1
	fi

	# apt upgrade
	apt-get upgrade -y

	# Install OpenSSH and other packages
	sudo add-apt-repository --yes universe
	if ! apt_update_with_fallback; then
		echo "FATAL: Failed to update package lists after adding universe repository"
		exit 1
	fi
	if ! apt_install_with_fallback install -y --no-install-recommends \
		openssh-server \
		git \
		ufw \
		cron \
		logrotate \
		fail2ban \
		locales \
		at \
		less \
		python3-systemd; then
		echo "FATAL: Failed to install universe packages"
		exit 1
	fi

	if [ "${ARCH}" = "arm64" ]; then
		if ! apt_install_with_fallback $APT_OPTIONS --yes install linux-aws initramfs-tools dosfstools; then
			echo "FATAL: Failed to install arm64 boot packages"
			exit 1
		fi
	fi
}

function setup_locale {
cat << EOF >> /etc/locale.gen
en_US.UTF-8 UTF-8
EOF

cat << EOF > /etc/default/locale
LANG="C.UTF-8"
LC_CTYPE="C.UTF-8"
EOF
	locale-gen en_US.UTF-8
}

function setup_postgesql_env {
	    # Create the directory if it doesn't exist
    sudo mkdir -p /etc/environment.d
    
    # Define the contents of the PostgreSQL environment file
    cat <<EOF | sudo tee /etc/environment.d/postgresql.env >/dev/null
LOCALE_ARCHIVE=/usr/lib/locale/locale-archive
LANG="en_US.UTF-8"
LANGUAGE="en_US.UTF-8"
LC_ALL="en_US.UTF-8"
LC_CTYPE="en_US.UTF-8"
EOF
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

	apt-get install -y --no-install-recommends llvm-11-dev clang-11
	# Mark llvm as manual to prevent auto removal
	apt-mark manual libllvm11:arm64
}

function setup_apparmor {
	if ! apt_install_with_fallback install -y apparmor apparmor-utils auditd; then
		echo "FATAL: Failed to install apparmor packages"
		exit 1
	fi

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
		if ! apt_install_with_fallback $APT_OPTIONS --yes install cloud-guest-utils fdisk grub-efi-arm64 efibootmgr; then
			echo "FATAL: Failed to install grub packages for arm64"
			exit 1
		fi
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
	# Set the static hostname
	echo "ubuntu" > /etc/hostname
	chmod 644 /etc/hostname
	# Update netplan configuration to not send hostname
	cat << EOF > /etc/netplan/01-hostname.yaml
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: true
      dhcp4-overrides:
        send-hostname: false
EOF
	# Set proper permissions for netplan security
	chmod 600 /etc/netplan/01-hostname.yaml
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
	# Set proper permissions for netplan security
	chmod 600 /etc/netplan/eth0.yaml
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

# Remove policy-rc.d so services start normally on boot
function enable_services {
	rm -f /usr/sbin/policy-rc.d
}

update_install_packages
setup_locale
setup_postgesql_env
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
enable_services
