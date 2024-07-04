#!/usr/bin/env bash
# shellcheck shell=bash

set -o errexit
set -o pipefail
set -o xtrace

function install_packages {
	# Setup Ansible on host VM
	sudo apt-get update && sudo apt-get install software-properties-common -y
	sudo add-apt-repository --yes --update ppa:ansible/ansible && sudo apt-get install ansible -y
	ansible-galaxy collection install community.general

}



function install_nix() {
    sudo su -c "curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install --no-confirm \
    --extra-conf \"substituters = https://cache.nixos.org https://nix-postgres-artifacts.s3.amazonaws.com\" \
    --extra-conf \"trusted-public-keys = nix-postgres-artifacts:dGZlQOvKcNEjvT7QEAJbcV6b6uk7VF/hWMjhYleiaLI=% cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=\" " -s /bin/bash root
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh

}


function execute_stage2_playbook {

sudo tee /etc/ansible/ansible.cfg <<EOF
[defaults]
callbacks_enabled = timer, profile_tasks, profile_roles
EOF
	# Run Ansible playbook
	#export ANSIBLE_LOG_PATH=/tmp/ansible.log && export ANSIBLE_DEBUG=True && export ANSIBLE_REMOTE_TEMP=/tmp 
	export ANSIBLE_LOG_PATH=/tmp/ansible.log && export ANSIBLE_REMOTE_TEMP=/tmp
	ansible-playbook /tmp/ansible-playbook/playbook.yml --extra-vars '{"nixpkg_mode": true, "stage2_nix": true, "debpkg_mode": false}' $ARGS
}


install_packages
install_nix
execute_stage2_playbook

