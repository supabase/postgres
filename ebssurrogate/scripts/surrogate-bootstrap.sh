#!/usr/bin/env bash
#
# This script creates filesystem and setups up chrooted
# enviroment for further processing. It also runs
# ansible playbook and finally does system cleanup.
#
# Adapted from: https://github.com/jen20/packer-ubuntu-zfs

set -o errexit
set -o pipefail
set -o xtrace

if [ $(dpkg --print-architecture) = "amd64" ]; 
then 
	ARCH="amd64";
else
        ARCH="arm64";
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
	# Setup Ansible on host VM
	apt-get update && sudo apt-get install software-properties-common -y
	add-apt-repository --yes --update ppa:ansible/ansible && sudo apt-get install ansible -y
	ansible-galaxy collection install community.general

	# Update apt and install required packages
	apt-get update
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
cat > "/mnt/etc/fstab" << EOF
$(printf "${FMT}" "# DEVICE UUID" "MOUNTPOINT" "TYPE" "OPTIONS" "DUMP" "FSCK")
$(findmnt -no SOURCE /mnt | xargs blkid -o export | awk -v FMT="${FMT}" '/^UUID=/ { printf(FMT, $0, "/", "ext4", "defaults,discard", "0", "1" ) }')
$(findmnt -no SOURCE /mnt/boot/efi | xargs blkid -o export | awk -v FMT="${FMT}" '/^UUID=/ { printf(FMT, $0, "/boot/efi", "vfat", "umask=0077", "0", "1" ) }')
$(findmnt -no SOURCE /mnt/data | xargs blkid -o export | awk -v FMT="${FMT}" '/^UUID=/ { printf(FMT, $0, "/data", "ext4", "defaults,discard", "0", "2" ) }')
$(printf "$FMT" "/swapfile" "none" "swap" "sw" "0" "0")
EOF
	unset FMT
}

function setup_chroot_environment {
	UBUNTU_VERSION=$(lsb_release -cs) # 'noble' for Ubuntu 24.04

	# Bootstrap Ubuntu into /mnt
	debootstrap --arch ${ARCH} --variant=minbase "$UBUNTU_VERSION" /mnt

	# Update ec2-region
	REGION=$(curl --silent --fail http://169.254.169.254/latest/meta-data/placement/availability-zone | sed -E 's|[a-z]+$||g')
	sed -i "s/REGION/${REGION}/g" /tmp/sources.list
	cp /tmp/sources.list /mnt/etc/apt/sources.list

	if [ "${ARCH}" = "arm64" ]; then
		create_fstab
	fi

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

	# Copy unit tests 
	cp -r /tmp/unit-tests /mnt/tmp/

	# Copy the bootstrap script into place and execute inside chroot
	cp /tmp/chroot-bootstrap.sh /mnt/tmp/chroot-bootstrap.sh
	chroot /mnt /tmp/chroot-bootstrap.sh
	rm -f /mnt/tmp/chroot-bootstrap.sh
	echo "${POSTGRES_SUPABASE_VERSION}" > /mnt/root/supabase-release

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

tee /etc/ansible/ansible.cfg <<EOF
[defaults]
callbacks_enabled = timer, profile_tasks, profile_roles
EOF
	# Run Ansible playbook
	#export ANSIBLE_LOG_PATH=/tmp/ansible.log && export ANSIBLE_DEBUG=True && export ANSIBLE_REMOTE_TEMP=/mnt/tmp 
	export ANSIBLE_LOG_PATH=/tmp/ansible.log && export ANSIBLE_REMOTE_TEMP=/mnt/tmp
	ansible-playbook -c chroot -i '/mnt,' /tmp/ansible-playbook/ansible/playbook.yml --extra-vars '{"debpkg_mode": true, "nixpkg_mode": false, "stage2_nix": false}' $ARGS
}

function update_systemd_services {
	# Disable vector service and set timer unit.
	cp -v /tmp/vector.timer /mnt/etc/systemd/system/vector.timer
	rm -f /mnt/etc/systemd/system/multi-user.target.wants/vector.service
	ln -s /etc/systemd/system/vector.timer /mnt/etc/systemd/system/multi-user.target.wants/vector.timer

	# Disable apparmor during first boot
	rm -f /mnt/etc/systemd/system/sysinit.target.wants/apparmor.service

	# Disable postgresql service during first boot.
	rm -f /mnt/etc/systemd/system/multi-user.target.wants/postgresql.service

	# Disable auditd
	rm -f /mnt/etc/systemd/system/multi-user.target.wants/auditd.service
}


function clean_system {
	# Copy cleanup scripts
	cp -v /tmp/ansible-playbook/scripts/90-cleanup.sh /mnt/tmp
	chmod +x /mnt/tmp/90-cleanup.sh
	chroot /mnt /tmp/90-cleanup.sh

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
#download_ccache
execute_playbook
update_systemd_services
#upload_ccache
clean_system
umount_reset_mappings
