#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

# shellcheck disable=SC2016 # backtick is literal markdown, not a command substitution
desc='Compares built package versions in `legacyPackages` between this PR and its base commit, per system.'

all_no_diff=true
for dir in diffs/diff-*; do
	file="$dir/diff.txt"
	if [ ! -f "$file" ] || ! grep -q '^No `legacyPackages' "$file"; then
		all_no_diff=false
		break
	fi
done

if [ "$all_no_diff" = "true" ]; then
	systems=$(for dir in diffs/diff-*; do echo "\`${dir#diffs/diff-}\`"; done | paste -sd', ')
	{
		echo "<!-- version-diff -->"
		echo "## Package version diff: none"
		echo "$desc"
		echo
		echo "### No Package Differences"
		echo "All packages are hash-identical on all systems (${systems})."
	} >/tmp/comment.md
else
	{
		echo "<!-- version-diff -->"
		echo "## Package version diff"
		echo "$desc"
		echo
		for dir in diffs/diff-*; do
			system="${dir#diffs/diff-}"
			file="$dir/diff.txt"
			if [ ! -f "$file" ]; then
				echo "<details>"
				echo "<summary>${system}: diff unavailable (job failed or skipped)</summary>"
				echo "</details>"
				echo
				continue
			fi
			if grep -q '^No `legacyPackages' "$file"; then
				# short, no-op case: summary alone, nothing to expand
				echo "<details>"
				echo "<summary>${system}: $(cat "$file")</summary>"
				echo "</details>"
				echo
				continue
			fi
			summary=$(grep '^Closure size:' "$file" | tail -1)
			echo "<details>"
			echo "<summary>${system}: ${summary:-changed}</summary>"
			echo
			echo '```'
			# cap the visible diff so a single arch can't blow the comment size limit
			head -c 20000 "$file"
			if [ "$(wc -c <"$file")" -gt 20000 ]; then
				echo
				echo "... truncated, see workflow run for full output ..."
			fi
			echo '```'
			echo "</details>"
			echo
		done
	} >/tmp/comment.md
fi
