#!/usr/bin/env bash
# shellcheck shell=bash

set -o errexit
set -o pipefail
set -o xtrace

exec 1>&2

function install_packages {
	# Setup Ansible on host VM
	apt-get update && apt-get install -y software-properties-common

	# Install EC2-specific packages that were deferred from stage 1
	# These packages have post-install scripts that need EC2 metadata service access
	# which only works on a real running EC2 instance (not in chroot)
	apt-get install -y ec2-hibinit-agent ec2-instance-connect hibagent

	# Manually add GPG key with explicit keyserver
	apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 93C4A3FD7BB9C367

	# Add repository and install
	# TODO (darora): temporarily disabling while Launchpad is under ddos attack and very frequently timing out
	# sudo add-apt-repository --yes ppa:ansible/ansible
	# sudo apt-get update
	apt-get install -y ansible

	ansible-galaxy collection install community.general
}

function install_nix() {
	curl -L https://releases.nixos.org/nix/nix-2.34.6/install | sh -s -- --yes --daemon --nix-extra-conf-file <(
		cat <<-EOF
			extra-experimental-features = nix-command flakes
			extra-substituters = https://nix-postgres-artifacts.s3.amazonaws.com
			extra-trusted-public-keys = nix-postgres-artifacts:dGZlQOvKcNEjvT7QEAJbcV6b6uk7VF/hWMjhYleiaLI=
		EOF
	)

	#shellcheck disable=SC1091
	. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
	nix --version
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
	apt-get -y remove --purge ansible
	# sudo add-apt-repository --yes --remove ppa:ansible/ansible
}

function report_disk_usage {
	read -r dub _ < <(du -sx -B1 /)
	read -r duh _ < <(du -sx -h /)
	printf '::notice::disk_usage bytes=%s human=%s\n' "$dub" "$duh" | tee -a /tmp/ansible.log
}

install_packages
install_nix
execute_stage2_playbook
cleanup_packages
report_disk_usage
