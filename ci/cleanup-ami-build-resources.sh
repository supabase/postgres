#!/usr/bin/env bash

set -uo pipefail

# default to dry run, opt in to destructive actions
RUN=--dry-run
if ${OK_TO_DESTROY:-false}; then
	RUN=--no-dry-run
fi

err() {
	echo "$@" >&2
}

usage() {
	err "Usage: $0 [--delete-amis] <build-execution-id>"
}

amis=false
if [[ ${1:-} == "--delete-amis" ]]; then
	amis=true
	shift
fi

execution_id=${1:-}
if [[ -z $execution_id ]] || (($# != 1)); then
	usage
	exit 2
fi

if [[ -z ${AWS_REGION:-} ]]; then
	err "AWS_REGION must be set"
	exit 2
fi

aws() {
	if [[ $RUN == --no-dry-run ]]; then
		command aws "$@"
		return
	fi

	local errfile ret=0
	errfile=$(mktemp)
	command aws "$@" 2> >(tee "$errfile" >&2) || ret=$?
	if ((ret != 0)) && grep -q DryRunOperation "$errfile"; then
		err "DryRunOperation error ignored"
		ret=0
	fi
	rm -f "$errfile"
	return $ret
}

failures=0
failed() {
	err "Cleanup failed: $*"
	failures=$((failures + 1))
}

ids() {
	local operation=$1
	local query=$2
	shift 2

	ids=() # purposefully not local, want it global and this resets it
	local output
	if ! output=$(aws ec2 "$operation" "$@" --query "$query" --output text); then
		failed "unable to list resources with $operation using arguments: $*"
		return 1
	fi

	output=${output//$'\n'/ }
	read -r -a ids <<<"$output"
	if ((${#ids[@]})); then
		return 0
	fi
	return 2
}

# Terminate instances and only wait for them once the terminate call itself succeeded,
# otherwise the waiter blocks for its full timeout on instances that were never told to stop.
terminate() {
	local kind=$1
	shift

	err "Terminating $kind instances: $*"
	if aws ec2 terminate-instances $RUN --instance-ids "$@" >/dev/null; then
		aws ec2 wait instance-terminated $RUN --instance-ids "$@" || failed "timed out waiting for $kind instances to terminate: $*"
	else
		failed "unable to terminate $kind instances: $*"
	fi
}

err "Cleaning up AMI build resources for execution $execution_id in $AWS_REGION"

status=Name=instance-state-name,Values=pending,running,stopping,stopped

# Testinfra instances use a separate tag with same value
args=(
	--filters
	"$status"
	"Name=tag:testinfra-run-id,Values=$execution_id"
	"Name=tag:creator,Values=testinfra-ci"
)
err "Searching for testinfra instances"
if ids describe-instances Reservations[].Instances[].InstanceId "${args[@]}"; then
	terminate testinfra "${ids[@]}"
fi

filters=(
	"Name=tag:packerExecutionId,Values=$execution_id"
	"Name=tag:creator,Values=packer"
	"Name=tag:appType,Values=postgres"
)
args=(--filters "$status" "${filters[@]}")

err "Searching for packer instances"
if ids describe-instances Reservations[].Instances[].InstanceId "${args[@]}"; then
	terminate Packer "${ids[@]}"
fi

status=Name=status,Values=available
args=(--filters "$status" "${filters[@]}")

err "Searching for network-interfaces"
if ids describe-network-interfaces NetworkInterfaces[].NetworkInterfaceId "${args[@]}"; then
	for id in "${ids[@]}"; do
		err "Deleting network interface: $id"
		aws ec2 delete-network-interface $RUN --network-interface-id "$id" || failed "unable to delete network interface: $id"
	done
fi

err "Searching for volumes"
if ids describe-volumes Volumes[].VolumeId "${args[@]}"; then
	for id in "${ids[@]}"; do
		err "Deleting volume: $id"
		aws ec2 delete-volume $RUN --volume-id "$id" || failed "unable to delete volume: $id"
	done
fi

args=(--filters "${filters[@]}")

err "Searching for security groups"
if ids describe-security-groups SecurityGroups[].GroupId "${args[@]}"; then
	for id in "${ids[@]}"; do
		err "Deleting security group: $id"
		deleted=false

		# AWS may return DependencyViolation until terminated instances release their ENIs
		for _ in {1..6}; do
			if aws ec2 delete-security-group $RUN --group-id "$id"; then
				deleted=true
				break
			fi
			sleep 10
		done
		$deleted || failed "unable to delete security group: $id"
	done
fi

err "Searching for key pairs"
if ids describe-key-pairs KeyPairs[].KeyPairId "${args[@]}"; then
	for id in "${ids[@]}"; do
		err "Deleting key pair: $id"
		aws ec2 delete-key-pair $RUN --key-pair-id "$id" || failed "unable to delete key pair: $id"
	done
fi

if $amis; then
	err "Searching for images"
	if ids describe-images Images[].ImageId --owners self "${args[@]}"; then
		for id in "${ids[@]}"; do
			err "Deregistering AMI: $id"
			aws ec2 deregister-image $RUN --image-id "$id" || failed "unable to deregister AMI: $id"
		done
	fi
fi

# Find any orphaned snapshots from a cancel before the AMI was finalized
err "Searching for orphaned snapshots"
if ids describe-snapshots Snapshots[].SnapshotId --owner-ids self "${args[@]}"; then
	# going to call ids again below which clobbers $ids, so copy to new var
	snapshots=("${ids[@]}")
	for snapshot in "${snapshots[@]}"; do
		if ids describe-images Images[].ImageId \
			--owners self \
			--filters "Name=block-device-mapping.snapshot-id,Values=$snapshot"; then
			continue
		elif (($? == 1)); then
			# error with aws command, skip for safety
			continue
		fi

		err "Deleting orphaned snapshot: $snapshot"
		aws ec2 delete-snapshot $RUN --snapshot-id "$snapshot" || failed "unable to delete orphaned snapshot: $snapshot"
	done
fi

if ((failures)); then
	err "Packer cleanup completed with $failures error(s)"
	exit 1
fi

err "Packer cleanup complete"
