#!/usr/bin/env bash

set -o errexit
set -o pipefail
set -o xtrace

# shellcheck source=/dev/null
source /tmp/provision-common.sh

#################
# stage1 things #
#################

function install_packages {
	packages=(
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
	install_ansible
}

function execute_playbook {
	run_playbook ./ansible/playbook.yml /mnt/tmp false true localhost local
}

#################
# stage2 things #
#################

function execute_stage2_playbook {
	run_playbook ./ansible/playbook.yml /tmp true true localhost local --extra-vars "$NIX_STORE_PATHS"
}

function clean_legacy_things {
	# removes things that are bundled for legacy reasons, but we can start without for our newer artifacts
	apt-mark auto zlib1g zlib1g-dev
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

	remove_unwanted_files

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
add_apt_mirror_fallback
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
