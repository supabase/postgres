#!/usr/bin/env bash
# shellcheck shell=bash

set -o errexit
set -o pipefail
set -o xtrace

# shellcheck source=/dev/null
source /tmp/provision-common.sh

exec 1>&2

function setup_apt {
	export DEBIAN_FRONTEND=noninteractive
}

function install_packages {
	apt-get install -y ansible
	ansible-galaxy collection install community.general
}

function execute_stage2_playbook {
	echo "POSTGRES_MAJOR_VERSION: $POSTGRES_MAJOR_VERSION"
	echo "GIT_SHA: $GIT_SHA"

	# shellcheck disable=SC2086
	run_playbook /tmp/ansible-playbook/ansible/playbook.yml /tmp true false $ARGS
}

function cleanup_packages {
	apt-get remove --purge --yes ansible
}

setup_apt
update_and_upgrade_apt
install_packages
install_nix
execute_stage2_playbook
cleanup_packages
clean_nix
update_and_upgrade_apt
cleanup_apt
report_packages
report_disk_usage
