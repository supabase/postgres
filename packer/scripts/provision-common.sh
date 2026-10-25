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

function install_ansible {
	apt-get install --yes ansible
	ansible-galaxy collection install community.general
}

function install_nix() {
	local nix_version=2.35.3
	local nix_installer_sha256=69d0fe8fba8fe88f94c98b09964691ac9950abc7ecbf2ba861dc0533cfd901e9
	local nix_installer
	nix_installer=$(mktemp)
	curl -fsSL "https://releases.nixos.org/nix/nix-${nix_version}/install" -o "$nix_installer"
	echo "${nix_installer_sha256}  ${nix_installer}" | sha256sum -c -
	sh "$nix_installer" --yes --daemon --nix-extra-conf-file <(
		cat <<-EOF
			extra-experimental-features = nix-command flakes
			extra-substituters = https://nix-postgres-artifacts.s3.amazonaws.com
			extra-trusted-public-keys = nix-postgres-artifacts:dGZlQOvKcNEjvT7QEAJbcV6b6uk7VF/hWMjhYleiaLI=
		EOF
	)
	rm -f "$nix_installer"

	# shellcheck disable=SC1091
	. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
	nix --version
}

function run_playbook {
	local playbook=$1 remote_tmp=$2 stage2=$3 qemu=$4 host=$5 connection=$6
	shift 6

	mkdir -p /etc/ansible
	tee /etc/ansible/ansible.cfg <<-EOF
		[defaults]
		callbacks_enabled = timer, profile_tasks, profile_roles
	EOF

	export ANSIBLE_LOG_PATH=/tmp/ansible.log
	export ANSIBLE_REMOTE_TEMP=$remote_tmp

	ansible-playbook -c "$connection" -i "$host," "$playbook" \
		--extra-vars "{\"stage2\":$stage2,\"qemu\":$qemu}" \
		--extra-vars "psql_version=psql_$POSTGRES_MAJOR_VERSION" \
		--extra-vars "postgres_major_version=$POSTGRES_MAJOR_VERSION" \
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

function setup_apt {
	export DEBIAN_FRONTEND=noninteractive
}

function add_apt_mirror_fallback {
	# This function assumes deb822 formatted sources are in use, which is the case in both qemu and aws images
	# In aws cloud-init creates a sources file with regional mirrors for "default" Suites but keeps ubuntu for security suite
	# So we grab the first (only) URI from security and append it to non-security's URI
	# This ends up giving us fastest mirror for installs and falls back to ubuntu if there's an issue
	#
	# Note: Ubuntu amd64 mirrors have different hostnames for security vs non but aarch64 are the same, hence the amd64 specific line

	# ensure deb822 format sources are in use
	tail -n+1 /etc/apt/sources.list /etc/apt/sources.list.d/ubuntu.sources >&2

	local sources defmirror ubumirror
	sources=$(grep -e '^URIs\s*:' -e '^Suites\s*:' /etc/apt/sources.list.d/ubuntu.sources)
	defmirror=$(grep -B1 "$CODENAME-updates" <<<"$sources" | awk '/URIs/ {print $2}')
	ubumirror=$(grep -B1 "$CODENAME-security" <<<"$sources" | awk '/URIs/ {print $2}')
	if [[ $ARCH == amd64 ]]; then
		# amd64 hosts use security.ubuntu.com for security but archive.ubuntu.com for everything else
		ubumirror=${ubumirror/security/archive}
	fi

	if [[ $ubumirror == "$defmirror" ]]; then
		# Only using one mirror so nothing to add as fallback, not running in AWS maybe?
		return
	fi

	if grep -q "^URIs:.*$defmirror.*$ubumirror" /etc/apt/sources.list.d/ubuntu.sources; then
		echo "Ubuntu upstream is already a fallback, this is unexpected and needs source changes" >&2
		exit 1
	fi
	sed -i "s|$defmirror|& $ubumirror|" /etc/apt/sources.list.d/ubuntu.sources
}

function waitfor_boot_finished {
	while [[ ! -f /var/lib/cloud/instance/boot-finished ]]; do
		echo 'Waiting for cloud-init...'
		sleep 1
	done
}

function remove_unwanted_files {
	local root=${1:-}

	rm -rf "$root"/root/.cache
	rm -rf "$root"/root/.vpython*
	rm -rf "$root"/root/go
	rm -rf "$root"/usr/share/doc
}

function purge_packages {
	local common=(
		ansible
		autoconf
		automake
		autotools-dev
		cmake-data
		cpp-10
		cpp-9
		gcc-10
		gcc-9
		git
		git-man
		libcgal-dev
		libgcc-9-dev
		libicu-dev
	)

	apt-get --yes remove --purge "${common[@]}" "$@"
	apt-get --yes autoremove
	apt-get --yes autoclean
	apt-get --yes update
	apt-get --yes upgrade
}
