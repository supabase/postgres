#!/usr/bin/env bash
set -euo pipefail

system="$1"
head_json="/tmp/head-drvpaths/$system.json"
base_json="/tmp/base-drvpaths.json"

if diff -q <(jq -S . "$head_json") <(jq -S . "$base_json") >/dev/null; then
	echo "No \`legacyPackages.$system\` version changes in this PR." >/tmp/diff.txt
	cat /tmp/diff.txt
	exit 0
fi

changed=$(jq -r -n --slurpfile h "$head_json" --slurpfile b "$base_json" '
  ($h[0]) as $H | ($b[0]) as $B |
  ($H | keys) as $hk | ($B | keys) as $bk |
  ($hk - ($hk - $bk))[] | select($H[.] != $B[.])
')
added=$(jq -r -n --slurpfile h "$head_json" --slurpfile b "$base_json" '
  (($h[0] | keys) - ($b[0] | keys))[]
')
removed=$(jq -r -n --slurpfile h "$head_json" --slurpfile b "$base_json" '
  (($b[0] | keys) - ($h[0] | keys))[]
')

: >/tmp/diff.txt
for attr in $changed; do
	head_path=$(cd head && nix build --accept-flake-config ".#legacyPackages.$system.$attr" --no-link --print-out-paths)
	base_path=$(cd base && nix build --accept-flake-config ".#legacyPackages.$system.$attr" --no-link --print-out-paths)
	nix run --accept-flake-config nixpkgs#nvd -- diff "$base_path" "$head_path" >>/tmp/diff.txt
done
for attr in $added; do
	echo "+ $attr added" >>/tmp/diff.txt
done
for attr in $removed; do
	echo "- $attr removed" >>/tmp/diff.txt
done

if [ ! -s /tmp/diff.txt ]; then
	echo "No \`legacyPackages.$system\` version changes in this PR." >/tmp/diff.txt
fi
cat /tmp/diff.txt
