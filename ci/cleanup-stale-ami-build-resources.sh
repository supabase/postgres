#!/usr/bin/env bash

set -euo pipefail

# This script finds Packer resources and testinfra instances older than 48 hours across one AWS region.
# It uses each resource's timestamp, or Packer's creation tag where needed, to identify stale builds.
# It then groups the resources by execution ID and passes each ID to the shared cleanup script.
# Registered AMIs and the snapshots they reference are left intact.
# Snapshots are deliberately not used for discovery since they are continuously growing.
# Dangling snapshots are still deleted by the shared cleanup script when some other stale resource discovers it.

msg() {
	echo "$*" >&2
}

if [[ -z ${AWS_REGION:-} ]]; then
	msg "AWS_REGION must be set"
	exit 2
fi

cutoff=$(date -u -d '48 hours ago' '+%Y-%m-%dT%H:%M:%SZ')
msg "Looking for Packer and testinfra executions with resources created before $cutoff..."

# Each failure touches .failed/<id> (or .failed/gather) so it survives xargs subshells.
rm -rf .failed
mkdir -p .failed

readarray -t ids < <(
	{
		aws ec2 describe-instances \
			--filters \
			"Name=tag-key,Values=testinfra-run-id" \
			"Name=tag:creator,Values=testinfra-ci" \
			--output json |
			jq -r --arg cutoff "$cutoff" '.Reservations[].Instances[] | select(.LaunchTime < $cutoff)'

		args=(
			--filters
			'Name=tag-key,Values=packerExecutionId'
			'Name=tag:creator,Values=packer'
			'Name=tag:appType,Values=postgres'
			--output json
		)
		aws ec2 describe-instances "${args[@]}" |
			jq -r --arg cutoff "$cutoff" '.Reservations[].Instances[] | select(.LaunchTime < $cutoff)'

		aws ec2 describe-volumes "${args[@]}" |
			jq -r --arg cutoff "$cutoff" '.Volumes[] | select(.CreateTime < $cutoff)'

		aws ec2 describe-key-pairs "${args[@]}" |
			jq -r --arg cutoff "$cutoff" '.KeyPairs[] | select(.CreateTime < $cutoff)'

		aws ec2 describe-network-interfaces "${args[@]}" |
			jq -r --arg cutoff "$cutoff" '.NetworkInterfaces[] | select(any(.TagSet[]?; .Key == "supaCreatedAt" and .Value < $cutoff))'

		aws ec2 describe-security-groups "${args[@]}" |
			jq -r --arg cutoff "$cutoff" '.SecurityGroups[] | select(any(.Tags[]?; .Key == "supaCreatedAt" and .Value < $cutoff))'
	} |
		jq -r '(.Tags[]?, .TagSet[]?) | select(.Key == "packerExecutionId" or .Key == "testinfra-run-id") | .Value' |
		sort -Vu
)

if ! wait $!; then
	msg "Encountered at least one error discovering stale executions, proceeding anyway"
	touch .failed/gather
fi
if ((${#ids[@]} == 0)); then
	msg "No stale Packer or testinfra executions found"
else
	msg "${#ids[@]} stale executions found"
fi

cleaner=$(dirname "$0")/cleanup-ami-build-resources.sh
# shellcheck disable=SC2016
printf '%s\n' "${ids[@]}" |
	xargs --no-run-if-empty -P"$(nproc)" -n1 bash -c '
		set -euo pipefail
		cleaner=$1
		id=$2

		sleep $((RANDOM%3)).$RANDOM # add some small jitter to try to avoid aws throttling

		"$cleaner" "$id" |& sed "s|^|$id |" && exit 0
		status=$?
		touch ".failed/$id"
		echo "Cleanup failed for execution $id with exit code $status" >&2
		exit 0
	' -- "$cleaner"

failures=$(find .failed -type f | wc -l)
if ((failures)); then
	msg "Stale cleanup completed with $failures error(s)"
	exit 1
fi
