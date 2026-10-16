#!/usr/bin/env bash

set -o errexit
set -o pipefail
set -o xtrace

# shellcheck source=/dev/null
source /tmp/provision-common.sh

#################
# stage1 things #
#################

function setup_apt {
	export DEBIAN_FRONTEND=noninteractive

	# This function assumes deb822 formatted sources are in use, which is the case in both qemu and aws images
	# In aws cloud-init creates a sources file with regional mirrors for "default" Suites but keeps ubuntu for security suite
	# So we grab the first (only) URI from security and append it to non-security's URI
	# This ends up giving us fastest mirror for installs and falls back to ubuntu if there's an issue
	#
	# Note: Ubuntu amd64 mirrors have different hostnames for security vs non but aarch64 are the same, hence the amd64 specific line

	# ensure deb822 format sources are in use
	tail -n+1 /etc/apt/sources.list /etc/apt/sources.list.d/ubuntu.sources >&2

	local sources defmirror ubumirror
	sources=$(grep -e '^URIs\s*:' -e '^Suites\s*:' /etc/apt/sources.list.d/ubuntu.sources)
	defmirror=$(grep -B1 "$CODENAME-updates" <<<"$sources" | awk '/URIs/ {print $2}')
	ubumirror=$(grep -B1 "$CODENAME-security" <<<"$sources" | awk '/URIs/ {print $2}')
	if [[ $ARCH == amd64 ]]; then
		# amd64 hosts use security.ubuntu.com for security but archive.ubuntu.com for everything else
		ubumirror=${ubumirror/security/archive}
	fi

	if [[ $ubumirror == "$defmirror" ]]; then
		# Only using one mirror so nothing to add as fallback, not running in AWS maybe?
		return
	fi

	if grep -q "^URIs:.*$defmirror.*$ubumirror" /etc/apt/sources.list.d/ubuntu.sources; then
		echo "Ubuntu upstream is already a fallback, this is unexpected and needs source changes" >&2
		exit 1
	fi
	sed -i "s|$defmirror|& $ubumirror|" /etc/apt/sources.list.d/ubuntu.sources
}

function waitfor_boot_finished {
	# Wait for cloudinit on the surrogate to complete before making progress
	while [[ ! -f /var/lib/cloud/instance/boot-finished ]]; do
		echo 'Waiting for cloud-init...'
		sleep 1
	done
}

function install_packages {
	packages=(
		ansible
		arptables
		e2fsprogs
		ebtables
		gpg
		iptables
		less
		locales
		logrotate
		nfs-common
		software-properties-common
		ufw
	)
	apt-get install --yes "${packages[@]}"
	ansible-galaxy collection install community.general
}

function execute_playbook {
	run_playbook ./ansible/playbook.yml /mnt/tmp false true \
		--extra-vars "postgresql_major=$POSTGRES_MAJOR_VERSION" \
		--extra-vars @./ansible/qemu-vars.yaml
}

#################
# stage2 things #
#################

function execute_stage2_playbook {
	run_playbook ./ansible/playbook.yml /tmp true true \
		--extra-vars "postgresql_major=$POSTGRES_MAJOR_VERSION" \
		--extra-vars @./ansible/qemu-vars.yaml
}

function clean_legacy_things {
	# removes things that are bundled for legacy reasons, but we can start without for our newer artifacts
	apt-mark auto zlib1g* # TODO (darora): need to make sure that there aren't other things that still need this
	apt-get purge --yes kong
}

function clean_system {
	# we do not want to ship an initialized DB as this is performed as needed
	mkdir -p /db/template
	mv /data/pgdata /db/template
	cloud-init clean --logs

	# Copy cleanup scripts
	chmod +x /tmp/cleanup-qemu.sh
	/tmp/cleanup-qemu.sh

	setup_image_logs

	# unwanted files
	rm -rf /root/.cache
	rm -rf /root/.vpython*
	rm -rf /root/go
	rm -rf /mnt/usr/share/doc

	# remove passwords in user-data-cloudimg.img (required for Packer login)
	usermod -p '*' ubuntu
	usermod -p '*' root

	# Ensure that PasswordAuthentication is off
	# From chroot-boostrap-nix.sh
	disable_sshd_passwd_auth

	if ! grep -qE "^PasswordAuthentication\s+no" /etc/ssh/sshd_config; then
		echo "ERROR: PasswordAuthentication is not disabled in sshd_config"
		exit 1
	fi
}

#################
# stage1 things #
#################

ARCH=$(dpkg --print-architecture)
: "${ARCH:?Failed to detect architecture}"
# shellcheck source=/dev/null
CODENAME=$(source /etc/os-release && echo "$VERSION_CODENAME")
: "${CODENAME:?Failed to detect OS codename}"

waitfor_boot_finished
setup_apt
update_and_upgrade_apt
install_packages
setup_postgesql_env
setup_locale
execute_playbook

#################
# stage2 things #
#################

install_nix
execute_stage2_playbook
clean_legacy_things
clean_system
clean_nix
cleanup_apt
report_packages
report_disk_usage
