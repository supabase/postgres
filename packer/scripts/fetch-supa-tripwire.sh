#!/usr/bin/env bash
# Usage: fetch-supa-tripwire.sh <amd64|arm64> <output-dir>
# Fetches the supa-tripwire archive from the internal artifacts bucket. Without access it
# warns and continues unless SUPA_TRIPWIRE_REQUIRED=1.
set -euo pipefail

arch=$1
dir=$2

case ${SUPA_TRIPWIRE_REQUIRED:-} in
'' | 1) ;;
*)
	echo "SUPA_TRIPWIRE_REQUIRED must be 1 or unset" >&2
	exit 1
	;;
esac

mkdir -p "$dir"
touch "$dir/.keep"

archive=supa-tripwire-v$(yq -er .supa_tripwire_release ansible/vars.yml)-$arch.tar.xz
if ! aws s3 cp --only-show-errors --region us-east-1 "s3://supabase-internal-artifacts/supa-tripwire/$archive" "$dir/$archive"; then
	if [[ ${SUPA_TRIPWIRE_REQUIRED:-} == 1 ]]; then
		echo "::error::could not fetch $archive" >&2
		exit 1
	fi
	echo "::warning::could not fetch $archive, building without supa-tripwire" >&2
fi
