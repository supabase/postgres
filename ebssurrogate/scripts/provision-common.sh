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

function setup_locale {
	cat >>/etc/locale.gen <<-EOF
		en_US.UTF-8 UTF-8
	EOF
	cat >/etc/default/locale <<-EOF
		LANG="C.UTF-8"
		LC_CTYPE="C.UTF-8"
	EOF
	locale-gen en_US.UTF-8
}

function setup_postgesql_env {
	mkdir -p /etc/environment.d

	tee /etc/environment.d/postgresql.env >/dev/null <<-EOF
		LOCALE_ARCHIVE=/usr/lib/locale/locale-archive
		LANG="en_US.UTF-8"
		LANGUAGE="en_US.UTF-8"
		LC_ALL="en_US.UTF-8"
		LC_CTYPE="en_US.UTF-8"
	EOF
}

function disable_sshd_passwd_auth {
	sed -i -E \
		-e 's/^#?\s*PasswordAuthentication\s+(yes|no)\s*$/PasswordAuthentication no/g' \
		-e 's/^#?\s*ChallengeResponseAuthentication\s+(yes|no)\s*$/ChallengeResponseAuthentication no/g' \
		/etc/ssh/sshd_config
}

function ensure_tmp_dir {
	# https://github.com/digitalocean/marketplace-partners/issues/94
	if [[ ! -d /tmp ]]; then
		mkdir /tmp
	fi
	chmod 1777 /tmp
}

function scrub_history {
	rm -rf /tmp/* /var/tmp/*
	history -c
	cat /dev/null >/root/.bash_history
	unset HISTFILE
}

function scrub_logs_and_keys {
	find /var/log -mtime -1 -type f -exec truncate -s 0 {} \;
	rm -rf /var/log/*.gz /var/log/*.[0-9] /var/log/*-????????
	rm -rf /var/lib/cloud/instances/*
	rm -f /root/.ssh/authorized_keys /etc/ssh/*key*
	touch /etc/ssh/revoked_keys
	chmod 600 /etc/ssh/revoked_keys
}

function zero_free_space {
	dd if=/dev/zero of=/zerofile &
	PID=$!
	while [ -d /proc/$PID ]; do
		printf "."
		sleep 5
	done
	sync
	rm /zerofile
	sync
}

function empty_login_records {
	cat /dev/null >/var/log/lastlog
	cat /dev/null >/var/log/wtmp
}

function setup_image_logs {
	local root=${1:-} run=()
	if [[ -n $root ]]; then
		run=(chroot "$root")
	fi

	rm -rf "$root"/var/log/*
	# https://github.com/fail2ban/fail2ban/issues/1593
	touch "$root/var/log/auth.log"

	touch "$root/var/log/pgbouncer.log"
	"${run[@]}" chown pgbouncer:postgres /var/log/pgbouncer.log

	mkdir -p "$root/var/log/postgresql"
	"${run[@]}" chown postgres:postgres /var/log/postgresql

	mkdir "$root/var/log/wal-g"
	touch "$root"/var/log/wal-g/{backup-push.log,backup-fetch.log,wal-push.log,wal-fetch.log,pitr.log}

	mkdir "$root/var/log/sysstat"

	"${run[@]}" chown -R postgres:postgres /var/log/wal-g
	# vector reads pitr.log; modes match the salt vector formula
	"${run[@]}" chmod -R 0310 /var/log/wal-g
	"${run[@]}" chmod 0340 /var/log/wal-g/pitr.log

	mkdir "$root/var/log/audit"
}
