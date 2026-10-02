# shellcheck shell=bash

set -x

# Parse required parameters
STAGE=${1:-stage1}
case $STAGE in
stage1 | stage2) ;;
*) echo "Error: Invalid stage '$STAGE'. Must be 'stage1' or 'stage2'" >&2 && exit 1 ;;
esac

ARCH=$2
case $ARCH in
amd64 | arm64) ;;
*) echo "Error: Invalid arch '$ARCH'. Must be 'amd64' or 'arm64'" >&2 && exit 1 ;;
esac
shift 2

if [[ -z ${AWS_REGION:-} ]]; then
	echo "AWS_REGION is required but unset" >&2
	exit 1
fi

INPUT_HASH=@out@
INPUT_HASH=${INPUT_HASH#/nix/store/}
INPUT_HASH=${INPUT_HASH%%-*}

export PACKER_LOG=${PACKER_LOG:-${RUNNER_DEBUG:-0}}
on_error=ask
if ${CI:-false}; then
	echo "::notice::Setting packer build -on-error=abort since this is CI, this is different than non-CI runs!"
	on_error=abort
elif ! [[ -t 0 ]]; then
	echo "stdin is not a tty, so running packer build -on-error=cleanup (default) since there's no one to ask!" >&2
	on_error=cleanup
fi

find_ami() {
	local arch
	case $ARCH in
	amd64) arch=x86_64 ;;
	arm64) arch=arm64 ;;
	esac

	postgresVersion=$1
	shift

	local filters=(
		"$@"
		"Name=architecture,Values=$arch"
		"Name=state,Values=available"
		"Name=tag:packerExecutionId,Values=$PACKER_EXECUTION_ID"
		"Name=tag:postgresVersion,Values=$postgresVersion"
		"Name=tag:sourceSha,Values=$GIT_SHA" # This is set by packer via the git-head-version var which is always passed in by the build-ami action
	)

	local ami_output exit_code
	ami_output=$(aws ec2 describe-images --owners self --filters "${filters[@]}" --query 'Images[0].ImageId' --output text 2>&1) || exit_code=$?

	if ((exit_code != 0)) && ((exit_code != 255)); then
		echo "Error querying AWS: $ami_output"
		exit 1
	fi

	if [[ $ami_output == "None" ]] || [[ -z $ami_output ]]; then
		echo ""
	else
		echo "$ami_output"
	fi
}

show_ami_info() {
	local stage=$1 id=$2
	if [[ -z $id ]]; then
		echo "Error: Stage $stage AMI not found, was there an error?" >&2
		exit 1
	fi

	if [[ -n ${GITHUB_OUTPUT:-} ]]; then
		AMI_NAME=$(aws ec2 describe-images --image-ids "$id" --query 'Images[0].Name' --output text)
		if [[ -n $AMI_NAME ]]; then
			echo "::notice title=Stage $stage AMI Built::AMI '$AMI_NAME' (ID: $id) built in region $AWS_REGION"
		fi
	fi
}

if [[ $STAGE == "stage1" ]]; then
	echo "Building stage 1..."

	cd @packerSources@ || exit 1
	packer init -var-file="packer/$ARCH.vars.pkr.hcl" packer/stage1-nix.pkr.hcl
	packer build -on-error=$on_error \
		-var-file="packer/$ARCH.vars.pkr.hcl" \
		-var "input-hash=$INPUT_HASH" \
		-var "postgres-version=$POSTGRES_VERSION" \
		-var "region=$AWS_REGION" \
		"$@" packer/stage1-nix.pkr.hcl

	STAGE1_AMI_ID=$(find_ami "$POSTGRES_VERSION-stage1" "Name=tag:inputHash,Values=$INPUT_HASH")
	show_ami_info 1 "$STAGE1_AMI_ID"

elif [[ $STAGE == "stage2" ]]; then
	echo "Building stage 2..."

	STAGE1_AMI_ID=$(find_stage1_ami)
	if [[ -z $STAGE1_AMI_ID ]]; then
		echo "Error: Stage 1 AMI not found. Please build stage 1 first."
		exit 1
	fi

	echo "Found stage 1 AMI: $STAGE1_AMI_ID"

	packer init -var-file="packer/$ARCH.vars.pkr.hcl" packer/stage2-nix.pkr.hcl
	packer build -on-error=$on_error \
		-var-file="packer/$ARCH.vars.pkr.hcl" \
		-var "region=$AWS_REGION" \
		-var "source_ami=$STAGE1_AMI_ID" \
		"$@" packer/stage2-nix.pkr.hcl

	disk_usage_notice=$(grep '^::notice::disk_usage ' /tmp/ansible-stage2.log | tail -n 1 || true)
	disk_usage_notice_pattern='^::notice::disk_usage bytes=([0-9]+) human=([0-9]+(\.[0-9]+)?[MGT]?)$'
	if [[ $disk_usage_notice =~ $disk_usage_notice_pattern ]]; then
		disk_usage_bytes=${BASH_REMATCH[1]}
		disk_usage_human=${BASH_REMATCH[2]}
	else
		echo "Error: Missing or invalid disk usage notice in stage 2 log: '$disk_usage_notice'" >&2
		exit 1
	fi
	echo "::notice::AMI Disk Usage $disk_usage_human $disk_usage_bytes"

	if [[ -n ${GITHUB_OUTPUT:-} ]]; then
		disk_usage_json=$(jq -cnr --arg bytes "$disk_usage_bytes" --arg human "$disk_usage_human" '{$bytes,$human}')
		echo "disk_usage_json=$disk_usage_json" >>"$GITHUB_OUTPUT"
	fi

	STAGE2_AMI_ID=$(find_ami "$POSTGRES_VERSION")
	show_ami_info 2 "$STAGE2_AMI_ID"
fi
