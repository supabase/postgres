# shellcheck shell=bash

set -euxo pipefail

die() {
	echo "error: $*" >&2
	exit 1
}

[[ -n ${AWS_REGION:-} ]] || die "AWS_REGION is required but unset"
export PACKER_LOG=${RUNNER_DEBUG:-0}

declare arch='' git_sha='' packages_git_sha='' postgres_major_version=''
while (($#)); do
	value=${2:-}
	case $1 in
	--arch) arch=$value ;;
	--git-sha) git_sha=$value ;;
	--packages-git-sha) packages_git_sha=$value ;;
	--postgres-major-version) postgres_major_version=$value ;;
	*) die "unknown option '$1'" ;;
	esac
	[[ -n $value && $value != --* ]] || die "missing value for $1"
	shift 2
done

required_arg() {
	local name=$1 value=$2
	[[ -n $value ]] || die "--$name is required"
}

required_arg git-sha "$git_sha"
required_arg arch "$arch"
case $arch in
amd64) aws_arch=x86_64 system=x86_64-linux ;;
arm64) aws_arch=arm64 system=aarch64-linux ;;
*) die "invalid arch '$arch', must be 'amd64' or 'arm64'" ;;
esac

required_arg postgres-major-version "$postgres_major_version"
case $postgres_major_version in
15 | 17 | orioledb-17) ;;
*) die "invalid PostgreSQL major version '$postgres_major_version', must be '15'; '17'; or 'orioledb-17'" ;;
esac

on_error=cleanup
if [[ ${CI:-false} == true ]]; then
	[[ -n ${GITHUB_RUN_ID:-} ]] || die "GITHUB_RUN_ID is required when CI=true"
	packer_execution_id=$postgres_major_version-$arch-$GITHUB_RUN_ID
else
	packer_execution_id=$postgres_major_version-$arch-$git_sha
	[[ -t 0 ]] && on_error=ask # not CI and stdin is a tty, so maybe we should ask what to do on error
fi

packages_git_sha=${packages_git_sha:-$git_sha}

input_hash=@out@
input_hash=${input_hash#/nix/store/}
input_hash=${input_hash%%-*}

# must run before the cd otherwise we get an error like `error: installable '/nix/store/...-amiSources' does not correspond to a Nix language value`
nix_store_paths=$(cat "$(nix build --no-link --print-out-paths "github:supabase/postgres/$packages_git_sha#packages.$system.nix-store-paths-$postgres_major_version")")

cd @amiSources@

postgres_release_version=$(yq -er ".postgres_release.postgres$postgres_major_version" ansible/postgres_release.yml) || die "unknown PostgreSQL major version '$postgres_major_version'"

ami_name=supabase-postgres-$aws_arch
if [[ ${AMI_RELEASE:-false} != true ]]; then
	postgres_release_version+=-g${git_sha:0:12}
fi
ami_name+=-$postgres_release_version

write_output() {
	if [[ -n ${GITHUB_OUTPUT:-} ]]; then
		printf '%s=%s\n' "$1" "$2" >>"$GITHUB_OUTPUT"
	fi
}

find_ami() {
	local postgresVersion=$1
	shift

	local filters=(
		"$@"
		"Name=architecture,Values=$aws_arch"
		"Name=state,Values=available"
		"Name=tag:packerExecutionId,Values=$packer_execution_id"
		"Name=tag:postgresVersion,Values=$postgresVersion"
		"Name=tag:sourceSha,Values=$git_sha"
	)

	local ami_output
	ami_output=$(aws ec2 describe-images --owners self --filters "${filters[@]}" --query 'Images[0].ImageId' --output text) || die "error querying AWS for an AMI"

	if [[ $ami_output == "None" ]] || [[ -z $ami_output ]]; then
		echo ""
	else
		echo "$ami_output"
	fi
}

show_ami_info() {
	local stage=$1 id=$2 name=$3
	if [[ -z $id ]]; then
		echo "Error: Stage $stage AMI not found, was there an error?" >&2
		exit 1
	fi

	echo "::notice title=Stage $stage AMI Built::AMI '$name' (ID: $id) built in region $AWS_REGION"
	write_output "stage${stage}_ami_id" "$id"
}

common_packer_args=(
	-on-error "$on_error"
	-var "git-head-version=$git_sha"
	-var "packer-execution-id=$packer_execution_id"
	-var "postgres-version=$postgres_release_version"
	-var "postgres_major_version=$postgres_major_version"
	-var-file "packer/$arch.vars.pkr.hcl"
)

# both templates require the same plugins, so one init covers both stages
packer init -var-file "packer/$arch.vars.pkr.hcl" packer/stage1-nix.pkr.hcl

echo "::group::AMI Build: Stage 1"

packer build "${common_packer_args[@]}" \
	-var "ami_name=$ami_name-stage-1" \
	-var "input-hash=$input_hash" \
	packer/stage1-nix.pkr.hcl

stage1_ami_id=$(find_ami "$postgres_release_version-stage1" "Name=tag:inputHash,Values=$input_hash")
show_ami_info 1 "$stage1_ami_id" "$ami_name-stage-1"

echo "::endgroup::"

echo "::group::AMI Build: Stage 2"

packer build "${common_packer_args[@]}" \
	-var "ami_name=$ami_name" \
	-var "nix_store_paths=$nix_store_paths" \
	-var "source_ami=$stage1_ami_id" \
	packer/stage2-nix.pkr.hcl

disk_usage_notice=$(grep '^::notice::disk_usage ' /tmp/ansible-stage2.log | tail -n 1 || true)
disk_usage_notice_pattern='^::notice::disk_usage bytes=([0-9]+) human=([0-9]+(\.[0-9]+)?[MGT]?)$'
if [[ $disk_usage_notice =~ $disk_usage_notice_pattern ]]; then
	disk_usage_bytes=${BASH_REMATCH[1]}
	disk_usage_human=${BASH_REMATCH[2]}
else
	die "missing or invalid disk usage notice in stage 2 log: '$disk_usage_notice'"
fi
echo "::notice::AMI Disk Usage $disk_usage_human $disk_usage_bytes"

disk_usage_json=$(jq -cnr --arg bytes "$disk_usage_bytes" --arg human "$disk_usage_human" '{$bytes,$human}')
write_output disk_usage_json "$disk_usage_json"

stage2_ami_id=$(find_ami "$postgres_release_version")
show_ami_info 2 "$stage2_ami_id" "$ami_name"

echo "::endgroup::"

write_output postgres_release_version "$postgres_release_version"
write_output execution_id "$packer_execution_id"
