#!/usr/bin/env bash
# shellcheck shell=bash

set -o errexit
set -o pipefail
set -o xtrace

# shellcheck source=/dev/null
source /tmp/provision-common.sh

exec 1>&2

function execute_stage2_playbook {
	echo "POSTGRES_MAJOR_VERSION: $POSTGRES_MAJOR_VERSION"
	run_playbook /tmp/ansible-playbook/ansible/playbook.yml /tmp true false localhost local --extra-vars "$NIX_STORE_PATHS"
}

function cleanup_packages {
	apt-get remove --purge --yes ansible
}

setup_apt
update_and_upgrade_apt
install_ansible
install_nix
execute_stage2_playbook
cleanup_packages
clean_nix
update_and_upgrade_apt
cleanup_apt
report_packages
report_disk_usage
