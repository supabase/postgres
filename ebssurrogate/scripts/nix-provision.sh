#!/usr/bin/env bash
# shellcheck shell=bash

set -o errexit
set -o pipefail
set -o xtrace

exec 1>&2

function setup_apt {
	export DEBIAN_FRONTEND=noninteractive
}

function cleanup_apt {
	apt-get clean
	apt-get autoremove --purge --yes
	rm -rf /var/lib/apt/lists/*
}

function update_and_upgrade_apt {
	apt-get update --yes
	apt-get dist-upgrade --yes
}

function install_packages {
	sudo apt-get install -y ansible
	ansible-galaxy collection install community.general
}

function install_nix() {
	if [[ ! -x /nix/var/nix/profiles/default/bin/nix-daemon ]]; then
		curl -L https://releases.nixos.org/nix/nix-2.34.6/install | sh -s -- --yes --daemon --nix-extra-conf-file <(
			cat <<-EOF
				extra-experimental-features = nix-command flakes
				extra-substituters = https://nix-postgres-artifacts.s3.amazonaws.com
				extra-trusted-public-keys = nix-postgres-artifacts:dGZlQOvKcNEjvT7QEAJbcV6b6uk7VF/hWMjhYleiaLI=
			EOF
		)
	fi
	mkdir -p /nix/var/nix/daemon-socket
	rm -f /nix/var/nix/daemon-socket/socket
	/nix/var/nix/profiles/default/bin/nix-daemon &
	NIX_DAEMON_PID=$!
	for _ in {1..50}; do
		[ -S /nix/var/nix/daemon-socket/socket ] && break
		sleep 0.1
	done
	if [ ! -S /nix/var/nix/daemon-socket/socket ]; then
		echo "Nix daemon failed to create its socket"
		exit 1
	fi
	trap stop_nix_daemon EXIT

	echo 'export NIX_REMOTE=daemon' >>/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh

	#shellcheck disable=SC1091
	. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
	nix --version
}

function stop_nix_daemon {
	kill "$NIX_DAEMON_PID" || true
	wait "$NIX_DAEMON_PID" || true
}

function execute_stage2_playbook {
	echo "POSTGRES_MAJOR_VERSION: $POSTGRES_MAJOR_VERSION"
	echo "GIT_SHA: $GIT_SHA"
	mkdir -p /etc/ansible
	tee /etc/ansible/ansible.cfg <<-EOF
		[defaults]
		callbacks_enabled = timer, profile_tasks, profile_roles
	EOF
	sed -i 's/- hosts: all/- hosts: localhost/' /tmp/ansible-playbook/ansible/playbook.yml

	# Run Ansible playbook
	export ANSIBLE_LOG_PATH=/tmp/ansible.log
	export ANSIBLE_REMOTE_TEMP=/tmp

	# shellcheck disable=SC2086
	ansible-playbook /tmp/ansible-playbook/ansible/playbook.yml \
		--extra-vars '{"stage2":true, "qemu":false}' \
		--extra-vars "git_commit_sha=$GIT_SHA" \
		--extra-vars "psql_version=psql_$POSTGRES_MAJOR_VERSION" \
		--extra-vars "postgresql_version=postgresql_$POSTGRES_MAJOR_VERSION" \
		--extra-vars "nix_secret_key=$NIX_SECRET_KEY" \
		--extra-vars "postgresql_major_version=$POSTGRES_MAJOR_VERSION" \
		$ARGS
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
update_and_upgrade_apt
cleanup_apt
apt list --installed | awk -F/ '{print $1}' && echo Finished
