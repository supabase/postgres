#!/usr/bin/env bash
# Each case is <name>.<system>.jsonl plus either <name>.<system>.expected.json
# (stdout must match, exit 0) or <name>.<system>.expected.txt (stdout must
# match, exit 1).
set -euo pipefail

cd "$(dirname "$0")"
failed=0

for input in cases/*.jsonl; do
	base=${input%.jsonl}
	system=${base##*.}
	name=$(basename "$base")

	if [[ -e $base.expected.json ]]; then
		expected=$(jq -S . "$base.expected.json")
		if actual=$(jq -r -S -s --arg system "$system" -f ../github-matrix.jq "$input") && [[ $actual == "$expected" ]]; then
			echo "ok   $name"
		else
			echo "FAIL $name"
			diff <(echo "$expected") <(echo "$actual") || true
			failed=1
		fi
	else
		expected=$(cat "$base.expected.txt")
		if actual=$(jq -r -s --arg system "$system" -f ../github-matrix.jq "$input" 2>/dev/null); then
			echo "FAIL $name: expected exit 1"
			failed=1
		elif [[ $actual == "$expected" ]]; then
			echo "ok   $name"
		else
			echo "FAIL $name"
			diff <(echo "$expected") <(echo "$actual") || true
			failed=1
		fi
	fi
done

exit $failed
