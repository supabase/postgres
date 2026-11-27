#!/usr/bin/env bash

set -euo pipefail

# Renders the pg_regress / pg_isolation_regress diffs printed by nix/checks.nix
# as a collapsible GitHub Actions job summary, so a failing check does not
# require digging through the raw nix build log to see what changed.
#
# Usage: regression-diffs-to-summary.sh <nix-build-log> [max-bytes]
#
# The blocks are delimited by the REGRESSION DIFFS BEGIN/END markers emitted
# from nix/checks.nix. nix prefixes each builder line with "<derivation> ", so
# that prefix is stripped before the diff is rendered.

log_file=${1:-}
max_bytes=${2:-65536}

if [[ -z $log_file || ! -f $log_file ]]; then
	exit 0
fi

content=$(
	awk '
	function strip_prefix(line) {
		sub(/^[A-Za-z0-9][A-Za-z0-9._+-]*> /, "", line)
		return line
	}
	/REGRESSION DIFFS BEGIN/ {
		capture = 1
		print ""
		print strip_prefix($0)
		print ""
		next
	}
	/REGRESSION DIFFS END/ {
		if (capture) {
			capture = 0
			print strip_prefix($0)
			print ""
		}
		next
	}
	capture {
		print strip_prefix($0)
	}
	' "$log_file"
)

# Avoid adding an empty summary when this was a non-check failure.
if [[ -z $(printf '%s' "$content" | tr -d '[:space:]') ]]; then
	exit 0
fi

truncated=0
if ((${#content} > max_bytes)); then
	content=${content:0:max_bytes}
	truncated=1
fi

# Use a fence longer than any backtick run in the diff so the block cannot be
# terminated early by its contents.
max_backticks=$(printf '%s' "$content" | { grep -o '`\+' || true; } | awk 'length > max { max = length } END { print max + 0 }')
fence=$(printf '%*s' $((max_backticks + 3)) '' | tr ' ' '`')

{
	echo "## pg_regress failure details"
	echo
	echo "<details><summary>Show regression.diffs</summary>"
	echo
	echo "${fence}diff"
	printf '%s\n' "$content"
	echo "$fence"
	if ((truncated)); then
		echo
		echo "_Diff truncated to ${max_bytes} bytes; see the build log for the full output._"
	fi
	echo
	echo "</details>"
}
