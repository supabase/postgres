#!/usr/bin/env bash

set -euo pipefail

# The script finds Packer resources and testinfra instances older than 24 hours across one AWS region.
# It uses each resource's timestamp, or Packer's creation tag for security groups, to identify stale builds.
# It then groups the resources by execution ID and passes each ID to the shared cleanup script.
# Registered AMIs and the snapshots they reference are left intact.

if [[ -z ${AWS_REGION:-} ]]; then
	echo "AWS_REGION must be set" >&2
	exit 2
fi

msg() {
	echo "$*" >&2
}

cutoff=$(date -u -d '24 hours ago' '+%Y-%m-%dT%H:%M:%SZ')
msg "Looking for Packer and testinfra executions with resources created before $cutoff..."

args=(
	--filters 'Name=tag-key,Values=packerExecutionId' 'Name=tag:appType,Values=postgres'
	--output json
)
readarray -t ids < <(
	{
		{
			msg "testinfra instances"
			aws ec2 describe-instances \
				--filters \
				"Name=tag-key,Values=testinfra-run-id" \
				"Name=tag:creator,Values=testinfra-ci" \
				--output json
			msg "packer instances"
			aws ec2 describe-instances "${args[@]}"
		} |
			jq -r --arg cutoff "$cutoff" '.Reservations[].Instances[] | select(.LaunchTime < $cutoff)' |
			tee .stale-instances.json

		msg "volumes"
		aws ec2 describe-volumes "${args[@]}" |
			jq -r --arg cutoff "$cutoff" '.Volumes[] | select(.CreateTime < $cutoff)' |
			tee .stale-volumes.json

		msg "key pairs"
		aws ec2 describe-key-pairs "${args[@]}" |
			jq -r --arg cutoff "$cutoff" '.KeyPairs[] | select(.CreateTime < $cutoff)' |
			tee .stale-key-pairs.json

		msg "snapshots"
		aws ec2 describe-snapshots --owner-ids self "${args[@]}" |
			jq -r --arg cutoff "$cutoff" '.Snapshots[] | select(.StartTime < $cutoff)' |
			tee .stale-snapshots.json

		msg "security groups"
		aws ec2 describe-security-groups "${args[@]}" |
			jq -r --arg cutoff "$cutoff" '.SecurityGroups[] | select(any(.Tags[]?; .Key == "supaCreatedAt" and .Value < $cutoff))' |
			tee .stale-security-groups.json
	} |
		jq -r '.Tags[]? | select(.Key == "packerExecutionId" or .Key == "testinfra-run-id") | .Value' |
		sort -Vu |
		tee .ids.txt
)

if ((${#ids[@]} == 0)); then
	echo "No stale Packer or testinfra executions found" >&2
	exit 0
fi

cleaner=$(dirname "$0")/cleanup-ami-build-resources.sh
for id in "${ids[@]}"; do
	echo "$cleaner" "$id"
done
