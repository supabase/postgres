#!/usr/bin/env bash

set -o errexit
set -o pipefail
set -o xtrace

if [ $(dpkg --print-architecture) = "amd64" ]; then
	ARCH="amd64"
else
	ARCH="arm64"
fi

function waitfor_boot_finished {
	export DEBIAN_FRONTEND=noninteractive

	echo "args: ${ARGS}"
	# Wait for cloudinit on the surrogate to complete before making progress
	while [[ ! -f /var/lib/cloud/instance/boot-finished ]]; do
		echo 'Waiting for cloud-init...'
		sleep 1
	done
}

function install_packages {
	apt-get update && sudo apt-get install software-properties-common e2fsprogs nfs-common -y
	add-apt-repository --yes --update ppa:ansible/ansible && sudo apt-get install ansible -y
	ansible-galaxy collection install community.general
}

function execute_playbook {

	tee /etc/ansible/ansible.cfg <<EOF
[defaults]
callbacks_enabled = timer, profile_tasks, profile_roles
EOF
	# Run Ansible playbook
	export ANSIBLE_LOG_PATH=/tmp/ansible.log && export ANSIBLE_REMOTE_TEMP=/mnt/tmp
	ansible-playbook ./ansible/playbook.yml --extra-vars '{"nixpkg_mode": true, "debpkg_mode": false, "stage2_nix": false}' \
		--extra-vars "postgresql_version=postgresql_${POSTGRES_MAJOR_VERSION}" \
		--extra-vars "postgresql_major_version=${POSTGRES_MAJOR_VERSION}" \
		--extra-vars "postgresql_major=${POSTGRES_MAJOR_VERSION}" \
		--extra-vars "psql_version=psql_${POSTGRES_MAJOR_VERSION}"
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

function setup_locale {
	cat <<EOF >>/etc/locale.gen
en_US.UTF-8 UTF-8
EOF

	cat <<EOF >/etc/default/locale
LANG="C.UTF-8"
LC_CTYPE="C.UTF-8"
EOF
	locale-gen en_US.UTF-8
}

sed -i 's/- hosts: all/- hosts: localhost/' ansible/playbook.yml

waitfor_boot_finished
install_packages
setup_postgesql_env
setup_locale
execute_playbook

####################
# stage 2 things
####################

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
	export ANSIBLE_LOG_PATH=/tmp/ansible.log && export ANSIBLE_REMOTE_TEMP=/tmp
	ansible-playbook ./ansible/playbook.yml \
		--extra-vars '{"nixpkg_mode": false, "stage2_nix": true, "debpkg_mode": false, "qemu_mode": true}' \
		--extra-vars "git_commit_sha=${GIT_SHA}" \
		--extra-vars "postgresql_version=postgresql_${POSTGRES_MAJOR_VERSION}" \
		--extra-vars "postgresql_major_version=${POSTGRES_MAJOR_VERSION}" \
		--extra-vars "postgresql_major=${POSTGRES_MAJOR_VERSION}" \
		--extra-vars "psql_version=psql_${POSTGRES_MAJOR_VERSION}"
}

function clean_legacy_things {
    # removes things that are bundled for legacy reasons, but we can start without for our newer artifacts
    apt-get unmark zlib1g* # TODO (darora): need to make sure that there aren't other things that still need this
    apt-get -y purge kong
    apt-get autoremove -y
}

function clean_system {
	# Copy cleanup scripts
	chmod +x /tmp/ansible-playbook/scripts/90-cleanup-qemu.sh
	/tmp/ansible-playbook/scripts/90-cleanup-qemu.sh

	# # Cleanup logs
	rm -rf /var/log/*
	# # https://github.com/fail2ban/fail2ban/issues/1593
	touch /var/log/auth.log

	touch /var/log/pgbouncer.log
	chown pgbouncer:postgres /var/log/pgbouncer.log

	# # Setup postgresql logs
	mkdir -p /var/log/postgresql
	chown postgres:postgres /var/log/postgresql
	# # Setup wal-g logs
	mkdir /var/log/wal-g
	touch /var/log/wal-g/{backup-push.log,backup-fetch.log,wal-push.log,wal-fetch.log,pitr.log}

	# #Creatre Sysstat directory for SAR
	mkdir /var/log/sysstat

	chown -R postgres:postgres /var/log/wal-g
	chmod -R 0300 /var/log/wal-g

	# # audit logs directory for apparmor
	mkdir /var/log/audit

	# # unwanted files
	rm -rf /var/lib/apt/lists/*
	rm -rf /root/.cache
	rm -rf /root/.vpython*
	rm -rf /root/go
	rm -rf /mnt/usr/share/doc
}

install_nix
execute_stage2_playbook
# we do not want to ship an initialized DB as this is performed as needed
mkdir -p /db/template
mv /data/pgdata /db/template
clean_legacy_things
clean_system
cloud-init clean --logs
