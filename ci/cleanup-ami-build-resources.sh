#!/usr/bin/env bash

set -uo pipefail

usage() {
	echo "Usage: $0 [--delete-amis] <build-execution-id>" >&2
}

amis=false
if [[ ${1:-} == "--delete-amis" ]]; then
	amis=true
	shift
fi

execution_id=${1:-}
if [[ -z $execution_id || $# -ne 1 ]]; then
	usage
	exit 2
fi

if [[ -z ${AWS_REGION:-} ]]; then
	echo "AWS_REGION must be set" >&2
	exit 2
fi

failures=0

failed() {
	echo "Cleanup failed: $*" >&2
	failures=$((failures + 1))
}

ids() {
	local operation=$1
	local query=$2
	local output
	shift 2

	ids=()
	if ! output=$(aws ec2 "$operation" --filters "$@" --query "$query" --output text); then
		failed "unable to list resources with $operation using filters: $*"
		return 1
	fi
	read -r -a ids <<<"$output"
	if ((${#ids[@]})); then
		return 0
	fi
	return 2
}

echo "Cleaning up AMI build resources for execution $execution_id in $AWS_REGION" >&2

status=Name=instance-state-name,Values=pending,running,stopping,stopped

# Testinfra instances use a separate tag with same value
tag=Name=tag:testinfra-run-id,Values=$execution_id
if ids describe-instances Reservations[].Instances[].InstanceId $status "$tag"; then
	echo "Terminating testinfra instances: ${ids[*]}" >&2
	aws ec2 terminate-instances --instance-ids "${ids[@]}" >/dev/null || failed "unable to terminate testinfra instances: ${ids[*]}"
	aws ec2 wait instance-terminated --instance-ids "${ids[@]}" || failed "timed out waiting for testinfra instances to terminate: ${ids[*]}"
fi

tag=Name=tag:packerExecutionId,Values=$execution_id
if ids describe-instances Reservations[].Instances[].InstanceId $status "$tag"; then
	echo "Terminating Packer instances: ${ids[*]}" >&2
	aws ec2 terminate-instances --instance-ids "${ids[@]}" >/dev/null || failed "unable to terminate Packer instances: ${ids[*]}"
	aws ec2 wait instance-terminated --instance-ids "${ids[@]}" || failed "timed out waiting for Packer instances to terminate: ${ids[*]}"
fi

status=Name=status,Values=available
if ids describe-network-interfaces NetworkInterfaces[].NetworkInterfaceId $status "$tag"; then
	for id in "${ids[@]}"; do
		echo "Deleting network interface: $id" >&2
		aws ec2 delete-network-interface --network-interface-id "$id" || failed "unable to delete network interface: $id"
	done
fi

if ids describe-volumes Volumes[].VolumeId $status "$tag"; then
	for id in "${ids[@]}"; do
		echo "Deleting volume: $id" >&2
		aws ec2 delete-volume --volume-id "$id" || failed "unable to delete volume: $id"
	done
fi

if ids describe-security-groups SecurityGroups[].GroupId "$tag"; then
	for id in "${ids[@]}"; do
		echo "Deleting security group: $id" >&2
		deleted=false
		# AWS may return DependencyViolation until terminated instances release their ENIs
		for _ in {1..6}; do
			if aws ec2 delete-security-group --group-id "$id"; then
				deleted=true
				break
			fi
			sleep 10
		done
		$deleted || failed "unable to delete security group: $id"
	done
fi

if ids describe-key-pairs KeyPairs[].KeyPairId "$tag"; then
	for id in "${ids[@]}"; do
		echo "Deleting key pair: $id" >&2
		aws ec2 delete-key-pair --key-pair-id "$id" || failed "unable to delete key pair: $id"
	done
fi

if $amis; then
	if ids describe-images Images[].ImageId "$tag"; then
		for id in "${ids[@]}"; do
			echo "Deregistering AMI and deleting associated snapshots: $id" >&2
			aws ec2 deregister-image --image-id "$id" --delete-associated-snapshots || failed "unable to deregister AMI and delete associated snapshots: $id"
		done
	fi
fi

# Find any orphaned snapshots from a cancel before the AMI was finalized
if ids describe-snapshots Snapshots[].SnapshotId "$tag"; then
	# going to call ids again below which clobbers ids, so copy to new var
	snapshots=("${ids[@]}")
	for snapshot in "${snapshots[@]}"; do
		if ids describe-images Images[].ImageId "Name=block-device-mapping.snapshot-id,Values=$snapshot"; then
			continue
		elif (($? == 1)); then
			# error with aws command, skip for safety
			continue
		fi

		echo "Deleting orphaned snapshot: $snapshot" >&2
		aws ec2 delete-snapshot --snapshot-id "$snapshot" || failed "unable to delete orphaned snapshot: $snapshot"
	done
fi

if ((failures)); then
	echo "Packer cleanup completed with $failures error(s)" >&2
	exit 1
fi

echo "Packer cleanup complete" >&2
