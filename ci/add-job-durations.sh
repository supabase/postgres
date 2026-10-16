#!/usr/bin/env bash

set -euo pipefail

# Appends each region's job duration in seconds as a last tab-separated field to its summary line
# (see ci/summarize-cleanup-log.sh), editing the summary files in place. Regions without an entry
# in the durations file get "n/a". Lines that are already "region<TAB>n/a" are left alone.
#
# Usage: add-job-durations.sh <durations-file> <summary-file>...
# The durations file has one "region<TAB>seconds" line per region.

if (($# < 2)); then
	echo "Usage: $0 <durations-file> <summary-file>..." >&2
	exit 2
fi

durations=$1
shift

for file in "$@"; do
	tmp=$(mktemp)
	awk -F'\t' -v OFS='\t' 'NR == FNR { secs[$1] = $2; next } NF > 2 { $0 = $0 OFS (($1 in secs) ? secs[$1] : "n/a") } { print }' "$durations" "$file" >"$tmp"
	mv "$tmp" "$file"
done
