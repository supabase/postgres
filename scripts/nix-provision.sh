#!/usr/bin/env bash
# shellcheck shell=bash

set -o errexit
set -o pipefail
set -o xtrace

function install_packages {
    # Setup Ansible on host VM
    sudo apt-get update && sudo apt-get install -y software-properties-common

    # Install EC2-specific packages that were deferred from stage 1
    # These packages have post-install scripts that need EC2 metadata service access
    # which only works on a real running EC2 instance (not in chroot)
    sudo apt-get install -y ec2-hibinit-agent ec2-instance-connect hibagent

    # Manually add GPG key with explicit keyserver
    sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 93C4A3FD7BB9C367

    # Add repository and install
    sudo add-apt-repository --yes ppa:ansible/ansible
    sudo apt-get update
    sudo apt-get install -y ansible

    ansible-galaxy collection install community.general
}



function install_nix() {
    sudo su -c "sh <(curl -L https://releases.nixos.org/nix/nix-2.32.2/install) --yes --daemon --nix-extra-conf-file /dev/stdin <<EXTRA_NIX_CONF
extra-experimental-features = nix-command flakes
extra-substituters = https://nix-postgres-artifacts.s3.amazonaws.com
extra-trusted-public-keys = nix-postgres-artifacts:dGZlQOvKcNEjvT7QEAJbcV6b6uk7VF/hWMjhYleiaLI=
EXTRA_NIX_CONF" -s /bin/bash root
    #shellcheck disable=SC1091
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
}


function execute_stage2_playbook {
    echo "POSTGRES_MAJOR_VERSION: ${POSTGRES_MAJOR_VERSION}"
    echo "GIT_SHA: ${GIT_SHA}"
    sudo tee /etc/ansible/ansible.cfg <<EOF
[defaults]
callbacks_enabled = timer, profile_tasks, profile_roles
EOF
    sed -i 's/- hosts: all/- hosts: localhost/' /tmp/ansible-playbook/ansible/playbook.yml

    # Run Ansible playbook
    export ANSIBLE_LOG_PATH=/tmp/ansible.log && export ANSIBLE_REMOTE_TEMP=/tmp
    ansible-playbook /tmp/ansible-playbook/ansible/playbook.yml \
        --extra-vars '{"nixpkg_mode": false, "stage2_nix": true, "debpkg_mode": false}' \
        --extra-vars "git_commit_sha=${GIT_SHA}" \
        --extra-vars "psql_version=psql_${POSTGRES_MAJOR_VERSION}" \
        --extra-vars "postgresql_version=postgresql_${POSTGRES_MAJOR_VERSION}" \
        --extra-vars "nix_secret_key=${NIX_SECRET_KEY}" \
        --extra-vars "postgresql_major_version=${POSTGRES_MAJOR_VERSION}" \
        $ARGS
}

function cleanup_packages {
    sudo apt-get -y remove --purge ansible
    sudo add-apt-repository --yes --remove ppa:ansible/ansible
}

install_packages
install_nix
execute_stage2_playbook
cleanup_packages
