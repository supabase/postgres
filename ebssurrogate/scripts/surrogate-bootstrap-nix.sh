#!/usr/bin/env bash
#
# This script creates filesystem and setups up chrooted
# enviroment for further processing. It also runs
# ansible playbook and finally does system cleanup.
#
# Adapted from: https://github.com/jen20/packer-ubuntu-zfs

set -o errexit
set -o pipefail

# [diagnostic exit-trap] capture state at exit regardless of where bash dies.
# Fires on success and failure. No behavior change on success.
# Goal: identify which command exits 123 by capturing resource state,
# kernel dmesg (OOM-kill / ENOSPC), and the tail of ansible.log + 90-cleanup.log
# at the exact moment of exit.
dump_diag_on_exit() {
	rc=$?
	set +e +o pipefail +x
	if [ "${ARCH:-}" != "amd64" ]; then
		return 0
	fi

	echo "===================================================================="
	echo "[exit-trap] bash exiting with code $rc"
	echo "===================================================================="
	echo "[exit-trap] --- free -h ---"
	free -h 2>&1 || true
	echo "[exit-trap] --- df -h ---"
	df -h 2>&1 || true
	echo "[exit-trap] --- df -i (inodes) ---"
	df -i 2>&1 || true
	echo "[exit-trap] --- top memory processes (command names only) ---"
	ps -eo pid,ppid,comm,%mem,rss --sort=-rss | head -20 || true
	echo "[exit-trap] --- sanitized kernel signal counts ---"
	dmesg 2>/dev/null | grep -Eic 'out of memory|oom|killed process|kernel panic|panic|ext4|i/o error|no space left' || true
	echo "===================================================================="
	echo "[exit-trap] end. final code: $rc"
	echo "===================================================================="
}
trap dump_diag_on_exit EXIT

if [ $(dpkg --print-architecture) = "amd64" ];
then
	ARCH="amd64";
else
	ARCH="arm64";
fi

function enable_amd64_build_diagnostics {
	if [ "${ARCH}" != "amd64" ]; then
		return 0
	fi

	echo "==[amd64-diagnostic]== enabling build-time swap"
	if ! swapon --show=NAME --noheadings | grep -qx "/mnt/tmp/build-swapfile"; then
		if fallocate -l 4G /mnt/tmp/build-swapfile; then
			chmod 600 /mnt/tmp/build-swapfile
			mkswap /mnt/tmp/build-swapfile
			swapon /mnt/tmp/build-swapfile
		else
			echo "==[amd64-diagnostic]== unable to allocate build swap; continuing without it"
			rm -f /mnt/tmp/build-swapfile
		fi
	fi
	swapon --show
	free -h

	echo "==[amd64-diagnostic]== disabling OOM panic for diagnostic run"
	sysctl -w vm.panic_on_oom=0 || true
	sysctl -w kernel.panic=0 || true
}

function disable_amd64_build_diagnostics {
	if [ "${ARCH}" != "amd64" ]; then
		return 0
	fi

	echo "==[amd64-diagnostic]== disabling build-time swap"
	swapoff /mnt/tmp/build-swapfile 2>/dev/null || true
	rm -f /mnt/tmp/build-swapfile
}

function start_amd64_watchdog {
	if [ "${ARCH}" != "amd64" ]; then
		return 0
	fi

	(
		set +e +o pipefail +x
		while true; do
			mem_available_kb=$(awk '/MemAvailable/ {print $2}' /proc/meminfo 2>/dev/null || echo unknown)
			root_used=$(df -P / 2>/dev/null | awk 'NR==2 {print $5}' || echo unknown)
			mnt_used=$(df -P /mnt 2>/dev/null | awk 'NR==2 {print $5}' || echo unknown)
			tmp_used=$(df -P /mnt/tmp 2>/dev/null | awk 'NR==2 {print $5}' || echo unknown)
			echo "==[amd64-watchdog $(date -Is)] mem_available_kb=${mem_available_kb} root=${root_used} mnt=${mnt_used} tmp=${tmp_used}=="
			sleep 60
		done
	) &
	WATCHDOG_PID=$!
}

function stop_amd64_watchdog {
	if [ -n "${WATCHDOG_PID:-}" ]; then
		kill "${WATCHDOG_PID}" 2>/dev/null || true
	fi
}

function amd64_phase {
	if [ "${ARCH}" = "amd64" ]; then
		echo "==[phase] $1 $(date -Is)=="
	fi
}

# Mirror fallback function for resilient apt-get update
function apt_update_with_fallback {
	local sources_file="/etc/apt/sources.list"
	local max_attempts=2
	local attempt=1

	# Get EC2 region if not already set
	if [ -z "${REGION}" ]; then
		REGION=$(curl --silent --fail http://169.254.169.254/latest/meta-data/placement/availability-zone | sed -E 's|[a-z]+$||g' || echo "")
	fi

	# Define mirror tiers (in priority order)
	local -a mirror_tiers=()
	if [ "${ARCH}" = "amd64" ]; then
		if [ -n "${REGION}" ]; then
			mirror_tiers+=("${REGION}.ec2.archive.ubuntu.com")
		fi
		mirror_tiers+=("archive.ubuntu.com")
	else
		if [ -n "${REGION}" ]; then
			mirror_tiers+=("${REGION}.clouds.ports.ubuntu.com")
		fi
		mirror_tiers+=("ports.ubuntu.com")
	fi

	# If we couldn't get REGION, skip tier 1
	if [ -z "${REGION}" ]; then
		echo "Warning: Could not determine EC2 region, skipping regional mirror"
		mirror_tiers=("${mirror_tiers[@]:1}")  # Remove first element
	fi

	for mirror in "${mirror_tiers[@]}"; do
		echo "========================================="
		echo "Attempting apt-get update with mirror: ${mirror}"
		echo "Attempt ${attempt} of ${max_attempts}"
		echo "========================================="

		# Update sources.list to use current mirror
		if [ "${ARCH}" = "amd64" ]; then
			sed -i "s|http://[^/]*/ubuntu/|http://${mirror}/ubuntu/|g" "${sources_file}"
		else
			sed -i "s|http://[^/]*/ubuntu-ports/|http://${mirror}/ubuntu-ports/|g" "${sources_file}"
			sed -i "s|http://ports.ubuntu.com/ubuntu-ports|http://${mirror}/ubuntu-ports|g" "${sources_file}"
		fi

		# Show what we're using
		echo "Current sources.list configuration:"
		grep -E '^deb ' "${sources_file}" | head -3

		# Attempt update with timeout (5 minutes)
		if timeout 300 apt-get update 2>&1; then
			echo "========================================="
			echo "✓ Successfully updated apt cache using mirror: ${mirror}"
			echo "========================================="
			return 0
		else
			local exit_code=$?
			echo "========================================="
			echo "✗ Failed to update using mirror: ${mirror}"
			echo "Exit code: ${exit_code}"
			echo "========================================="

			# Clean partial downloads
			apt-get clean
			rm -rf /var/lib/apt/lists/*

			# Exponential backoff before next attempt
			if [ ${attempt} -lt ${max_attempts} ]; then
				local sleep_time=$((attempt * 5))
				echo "Waiting ${sleep_time} seconds before trying next mirror..."
				sleep ${sleep_time}
			fi
		fi

		attempt=$((attempt + 1))
	done

	echo "========================================="
	echo "ERROR: All mirror tiers failed after ${max_attempts} attempts"
	echo "========================================="
	return 1
}

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
	# Setup Ansible on host VM
	if ! apt_update_with_fallback; then
		echo "FATAL: Failed to update package lists on host VM"
		exit 1
	fi

	sudo apt-get install software-properties-common -y
	# TODO (darora): temporarily disabling while Launchpad is under ddos attack and very frequently timing out
	# add-apt-repository --yes --update ppa:ansible/ansible

	if ! apt_update_with_fallback; then
		echo "FATAL: Failed to update package lists after adding Ansible PPA"
		exit 1
	fi

	sudo apt-get install ansible -y
	ansible-galaxy collection install community.general

	apt-get install -y \
		gdisk \
		e2fsprogs \
		debootstrap \
		nvme-cli
}

# Partition the new root EBS volume
function create_partition_table {

	if [ "${ARCH}" = "arm64" ]; then
		parted --script /dev/xvdf \
			 mklabel gpt \
	                 mkpart UEFI 1MiB 100MiB \
        	         mkpart ROOT 100MiB 100%
			 set 1 esp on \
			 set 1 boot on
		parted --script /dev/xvdf print
	else
		sgdisk -Zg -n1:0:4095 -t1:EF02 -c1:GRUB -n2:0:0 -t2:8300 -c2:EXT4 /dev/xvdf
	fi

	sleep 2
}

function device_partition_mappings {
	# NVMe EBS launch device mappings (symlinks): /dev/nvme*n* to /dev/xvd*
	declare -A blkdev_mappings
	for blkdev in $(nvme list | awk '/^\/dev/ { print $1 }'); do  # /dev/nvme*n*
	    # Mapping info from disk headers
	    header=$(nvme id-ctrl --raw-binary "${blkdev}" | cut -c3073-3104 | tr -s ' ' | sed 's/ $//g' | sed 's!/dev/!!')
	    mapping="/dev/${header%%[0-9]}"  # normalize sda1 => sda

	    # Create /dev/xvd* device symlink
	    if [[ ! -z "$mapping" ]] && [[ -b "${blkdev}" ]] && [[ ! -L "${mapping}" ]]; then
		ln -s "$blkdev" "$mapping"

		blkdev_mappings["$blkdev"]="$mapping"
	    fi
	done

	create_partition_table

	# NVMe EBS launch device partition mappings (symlinks): /dev/nvme*n*p* to /dev/xvd*[0-9]+
	declare -A partdev_mappings
	for blkdev in "${!blkdev_mappings[@]}"; do  # /dev/nvme*n*
	    mapping="${blkdev_mappings[$blkdev]}"

	    # Create /dev/xvd*[0-9]+ partition device symlink
	    for partdev in "${blkdev}"p*; do
		partnum=${partdev##*p}
		if [[ ! -L "${mapping}${partnum}" ]]; then
		    ln -s "${blkdev}p${partnum}" "${mapping}${partnum}"

		    partdev_mappings["${blkdev}p${partnum}"]="${mapping}${partnum}"
		fi
	    done
	done
}


#Download and install latest e2fsprogs for fast_commit feature,if required.
function format_and_mount_rootfs {
	mkfs.ext4 -m0.1 /dev/xvdf2

	mount -o noatime,nodiratime /dev/xvdf2 /mnt
	if [ "${ARCH}" = "arm64" ]; then
		mkfs.fat -F32 /dev/xvdf1
		mkdir -p /mnt/boot/efi
		sleep 2
		mount /dev/xvdf1 /mnt/boot/efi
	fi

	mkfs.ext4 /dev/xvdh

	# Explicitly reserving 100MiB worth of blocks for the data volume
	#
	# Any changes here should be propagated to $GIT_DATA_DIR/ansible/files/admin_api_scripts/grow_fs.sh
	RESERVED_DATA_VOLUME_BLOCK_COUNT=$((100 * 1024 * 1024 / 4096))
	tune2fs -r $RESERVED_DATA_VOLUME_BLOCK_COUNT /dev/xvdh

	mkdir -p /mnt/data
	mount -o defaults,discard /dev/xvdh /mnt/data
}

function create_swapfile {
	fallocate -l 1G /mnt/swapfile
	chmod 600 /mnt/swapfile
	mkswap /mnt/swapfile
}

function format_build_partition {
	mkfs.ext4 -O ^has_journal /dev/xvdc
}
function pull_docker {
	apt-get install -y docker.io
	docker run -itd --name ccachedata "${DOCKER_IMAGE}:${DOCKER_IMAGE_TAG}" sh
	docker exec -itd ccachedata mkdir -p /build/ccache
}

# Create fstab
function create_fstab {
	FMT="%-42s %-11s %-5s %-17s %-5s %s"
	local ROOT_LINE=$(findmnt -no SOURCE /mnt | xargs blkid -o export | awk -v FMT="${FMT}" '/^UUID=/ { printf(FMT, $0, "/", "ext4", "defaults,discard", "0", "1" ) }')
	local DATA_LINE=$(findmnt -no SOURCE /mnt/data | xargs blkid -o export | awk -v FMT="${FMT}" '/^UUID=/ { printf(FMT, $0, "/data", "ext4", "defaults,discard,nofail,x-systemd.device-timeout=5s", "0", "2" ) }')
	local SWAP_LINE=$(printf "$FMT" "/swapfile" "none" "swap" "sw" "0" "0")

	local EFI_LINE=""
	if [ "${ARCH}" = "arm64" ]; then
		EFI_LINE=$(findmnt -no SOURCE /mnt/boot/efi | xargs blkid -o export | awk -v FMT="${FMT}" '/^UUID=/ { printf(FMT, $0, "/boot/efi", "vfat", "umask=0077", "0", "1" ) }')
	fi

	{
		printf "${FMT}\n" "# DEVICE UUID" "MOUNTPOINT" "TYPE" "OPTIONS" "DUMP" "FSCK"
		echo "${ROOT_LINE}"
		[ -n "${EFI_LINE}" ] && echo "${EFI_LINE}"
		echo "${DATA_LINE}"
		echo "${SWAP_LINE}"
	} > "/mnt/etc/fstab"
	unset FMT
}

function setup_chroot_environment {
	UBUNTU_VERSION=$(lsb_release -cs) # 'noble' for Ubuntu 24.04

        # sometimes debootstrap will get stuck on a download for a long time
        # the default read timeout in wget is 900s, which can cause a ~15min increase in build time
        # this forces the process to fail-fast and retry
	cat <<EOF > ~/.wgetrc
read_timeout = 30
timeout = 35
tries = 5
EOF

	# Update ec2-region
	REGION=$(curl --silent --fail http://169.254.169.254/latest/meta-data/placement/availability-zone | sed -E 's|[a-z]+$||g')

	# Bootstrap Ubuntu into /mnt using the regional mirror (avoids global mirror stalls)
	if [ "${ARCH}" = "amd64" ]; then
		debootstrap --arch ${ARCH} --variant=minbase "$UBUNTU_VERSION" /mnt "http://${REGION}.ec2.archive.ubuntu.com/ubuntu"
	else
		debootstrap --arch ${ARCH} --variant=minbase "$UBUNTU_VERSION" /mnt "http://${REGION}.clouds.ports.ubuntu.com/ubuntu-ports"
	fi

	sed -i "s/REGION/${REGION}/g" /tmp/sources.list
	cp /tmp/sources.list /mnt/etc/apt/sources.list

	create_fstab

	# Create mount points and mount the filesystem
	mkdir -p /mnt/{dev,proc,sys}
	mount --rbind /dev /mnt/dev
	mount --rbind /proc /mnt/proc
	mount --rbind /sys /mnt/sys

        # Create build mount point and mount
	mkdir -p /mnt/tmp
	mount /dev/xvdc /mnt/tmp
	chmod 777 /mnt/tmp

	# Copy apparmor profiles
	chmod 644 /tmp/apparmor_profiles/*
	cp -r /tmp/apparmor_profiles /mnt/tmp/

	# Copy migrations
	cp -r /tmp/migrations /mnt/tmp/

	# Copy the bootstrap script into place and execute inside chroot
	cp /tmp/chroot-bootstrap-nix.sh /mnt/tmp/chroot-bootstrap-nix.sh
	chroot /mnt /tmp/chroot-bootstrap-nix.sh
	rm -f /mnt/tmp/chroot-bootstrap-nix.sh
	echo "${POSTGRES_SUPABASE_VERSION}" > /mnt/root/supabase-release

	# Copy the AMI version into the /etc/supabase-release file
	echo "${POSTGRES_SUPABASE_VERSION}" > /mnt/etc/supabase-release
	chmod 644 /mnt/etc/supabase-release

	# Copy the nvme identification script into /sbin inside the chroot
	mkdir -p /mnt/sbin
	cp /tmp/ebsnvme-id /mnt/sbin/ebsnvme-id
	chmod +x /mnt/sbin/ebsnvme-id

	# Copy the udev rules for identifying nvme devices into the chroot
	mkdir -p /mnt/etc/udev/rules.d
	cp /tmp/70-ec2-nvme-devices.rules \
		/mnt/etc/udev/rules.d/70-ec2-nvme-devices.rules

	#Copy custom cloud-init
	rm -f /mnt/etc/cloud/cloud.cfg
	cp /tmp/cloud.cfg /mnt/etc/cloud/cloud.cfg

	sleep 2
}

function download_ccache {
	docker cp ccachedata:/build/ccache/. /mnt/tmp/ccache
}

function execute_playbook {
	sudo mkdir -p /etc/ansible
tee /etc/ansible/ansible.cfg <<EOF
[defaults]
callbacks_enabled = timer, profile_tasks, profile_roles
pipelining = True
EOF
	# Run Ansible playbook
	#export ANSIBLE_LOG_PATH=/tmp/ansible.log && export ANSIBLE_DEBUG=True && export ANSIBLE_REMOTE_TEMP=/mnt/tmp
	export ANSIBLE_LOG_PATH=/tmp/ansible.log && export ANSIBLE_REMOTE_TEMP=/mnt/tmp
	ansible-playbook -c chroot -i '/mnt,' /tmp/ansible-playbook/ansible/playbook.yml \
	--extra-vars '{"nixpkg_mode": true, "debpkg_mode": false, "stage2_nix": false} ' \
	--extra-vars "psql_version=psql_${POSTGRES_MAJOR_VERSION}" \
	$ARGS
}

function update_systemd_services {
	# Disable vector service and set timer unit.
	cp -v /tmp/vector.timer /mnt/etc/systemd/system/vector.timer
	rm -f /mnt/etc/systemd/system/multi-user.target.wants/vector.service
	ln -s /etc/systemd/system/vector.timer /mnt/etc/systemd/system/multi-user.target.wants/vector.timer

	# Disable services during first boot.
	rm -f /mnt/etc/systemd/system/sysinit.target.wants/apparmor.service
	rm -f /mnt/etc/systemd/system/multi-user.target.wants/postgresql.service
	rm -f /mnt/etc/systemd/system/multi-user.target.wants/salt-minion.service

	# Disable auditd
	rm -f /mnt/etc/systemd/system/multi-user.target.wants/auditd.service
}


function clean_system {
	# Copy cleanup scripts
	cp -v /tmp/ansible-playbook/scripts/90-cleanup.sh /mnt/tmp
	chmod +x /mnt/tmp/90-cleanup.sh

	set +e
	chroot /mnt /tmp/90-cleanup.sh
	cleanup_rc=$?
	set -e
	echo "=============================================="
	echo "[diagnostic] 90-cleanup.sh exit code: ${cleanup_rc}"
	echo "[diagnostic] Last 300 lines of /mnt/tmp/90-cleanup.log:"
	echo "=============================================="
	tail -n 300 /mnt/tmp/90-cleanup.log 2>/dev/null || echo "[diagnostic] no log file present"
	echo "=============================================="
	echo "[diagnostic] end of 90-cleanup.log tail"
	echo "=============================================="
	if [ "${cleanup_rc}" -ne 0 ]; then
		exit "${cleanup_rc}"
	fi

	# Cleanup logs
	rm -rf /mnt/var/log/*
	# https://github.com/fail2ban/fail2ban/issues/1593
	touch /mnt/var/log/auth.log

	touch /mnt/var/log/pgbouncer.log
	if [ -f /usr/bin/chown ]; then
		chroot /mnt /usr/bin/chown pgbouncer:postgres /var/log/pgbouncer.log
	fi

	# Setup postgresql logs
	mkdir -p /mnt/var/log/postgresql
	if [ -f /usr/bin/chown ]; then
		chroot /mnt /usr/bin/chown postgres:postgres /var/log/postgresql
	fi

	# Setup wal-g logs
	mkdir /mnt/var/log/wal-g
	touch /mnt/var/log/wal-g/{backup-push.log,backup-fetch.log,wal-push.log,wal-fetch.log,pitr.log}

	#Creatre Sysstat directory for SAR
	mkdir /mnt/var/log/sysstat

	if [ -f /usr/bin/chown ]; then
		chroot /mnt /usr/bin/chown -R postgres:postgres /var/log/wal-g
		chroot /mnt /usr/bin/chmod -R 0300 /var/log/wal-g
	fi

	# audit logs directory for apparmor
	mkdir /mnt/var/log/audit

	# unwanted files
	rm -rf /mnt/var/lib/apt/lists/*
	rm -rf /mnt/root/.cache
	rm -rf /mnt/root/.vpython*
	rm -rf /mnt/root/go
	rm -rf /mnt/usr/share/doc

}

function upload_ccache {
	docker cp /mnt/tmp/ccache/. ccachedata:/build/ccache
	docker stop ccachedata
	docker commit ccachedata "${DOCKER_IMAGE}:${DOCKER_IMAGE_TAG}"
	echo ${DOCKER_PASSWD} | docker login --username ${DOCKER_USER} --password-stdin
	docker push  "${DOCKER_IMAGE}:${DOCKER_IMAGE_TAG}"
}

# Unmount bind mounts
function umount_reset_mappings {
	umount -l /mnt/dev
	umount -l /mnt/proc
	umount -l /mnt/sys
	umount -l /mnt/tmp
	if [ "${ARCH}" = "arm64" ]; then
		umount /mnt/boot/efi
	fi
	umount /mnt/data
	umount /mnt

	# Reset device mappings
	for dev_link in "${blkdev_mappings[@]}" "${partdev_mappings[@]}"; do
	    if [[ -L "$dev_link" ]]; then
		rm -f "$dev_link"
	    fi
	done
}

waitfor_boot_finished
install_packages
device_partition_mappings
format_and_mount_rootfs
create_swapfile
format_build_partition
#pull_docker
setup_chroot_environment
start_amd64_watchdog
#download_ccache
amd64_phase "before execute_playbook"
execute_playbook
amd64_phase "after execute_playbook"
enable_amd64_build_diagnostics
amd64_phase "before update_systemd_services"
update_systemd_services
amd64_phase "after update_systemd_services"
#upload_ccache
disable_amd64_build_diagnostics
amd64_phase "before clean_system"
clean_system
amd64_phase "after clean_system"
stop_amd64_watchdog
umount_reset_mappings
