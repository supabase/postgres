# shellcheck shell=bash

function update_and_upgrade_apt {
	apt-get update --yes
	apt-get dist-upgrade --yes
}

function cleanup_apt {
	apt-get clean
	apt-get autoremove --purge --yes
	rm -rf /var/lib/apt/lists/*
}

function install_nix() {
	curl -L https://releases.nixos.org/nix/nix-2.34.6/install | sh -s -- --yes --daemon --nix-extra-conf-file <(
		cat <<-EOF
			extra-experimental-features = nix-command flakes
			extra-substituters = https://nix-postgres-artifacts.s3.amazonaws.com
			extra-trusted-public-keys = nix-postgres-artifacts:dGZlQOvKcNEjvT7QEAJbcV6b6uk7VF/hWMjhYleiaLI=
		EOF
	)

	# shellcheck disable=SC1091
	. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
	nix --version
}

function run_playbook {
	local playbook=$1 remote_tmp=$2 stage2=$3 qemu=$4
	shift 4

	local sha_args=()
	if [[ $stage2 == true ]]; then
		sha_args=(--extra-vars "git_commit_sha=$GIT_SHA")
	fi

	mkdir -p /etc/ansible
	tee /etc/ansible/ansible.cfg <<-EOF
		[defaults]
		callbacks_enabled = timer, profile_tasks, profile_roles
	EOF
	sed -i 's/- hosts: all/- hosts: localhost/' "$playbook"

	export ANSIBLE_LOG_PATH=/tmp/ansible.log
	export ANSIBLE_REMOTE_TEMP=$remote_tmp

	ansible-playbook "$playbook" \
		--extra-vars "{\"stage2\":$stage2,\"qemu\":$qemu}" \
		"${sha_args[@]}" \
		--extra-vars "psql_version=psql_$POSTGRES_MAJOR_VERSION" \
		--extra-vars "postgresql_version=postgresql_$POSTGRES_MAJOR_VERSION" \
		--extra-vars "postgresql_major_version=$POSTGRES_MAJOR_VERSION" \
		"$@"
}

function clean_nix {
	nix-collect-garbage -d
	nix-store --optimise -v
}

function report_packages {
	# shellcheck disable=SC2016
	dpkg-query -W -f='${Package}\t${Version}\t${Architecture}\n' | LC_COLLATE=C.UTF-8 sort
	find /nix/store -maxdepth 1 | LC_COLLATE=C.UTF-8 sort -t- -k2
}

function report_disk_usage {
	read -r dub _ < <(du -sx -B1 /)
	read -r duh _ < <(du -sx -h /)
	printf '::notice::disk_usage bytes=%s human=%s\n' "$dub" "$duh" | tee -a /tmp/ansible.log
}
